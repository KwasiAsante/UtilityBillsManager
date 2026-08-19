import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import 'app_notification_store.dart';
import 'sse_service_native.dart';
import '../api/api_service.dart';
import '../bill_readiness/bill_readiness_service.dart';
import '../bill_summary/bill_summary_service.dart';
import '../../config/app_config.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/bill.dart';
import '../../data/models/rentor.dart';
import '../../data/models/sse_event.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../data/repositories/rentors_repository.dart';
import '../../helpers/bill_readiness/bill_notification_tracker_helper.dart';
import '../../screens/bill_summary/message_preview_screen.dart';
import '../../services/notification/notification_service.dart';
import '../../utils/app_logger.dart';

const initSettings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/launcher_icon'),
  iOS: DarwinInitializationSettings(),
  macOS: DarwinInitializationSettings(),
  linux: LinuxInitializationSettings(defaultActionName: 'Open'),
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger().d('[FCM] Background message: ${message.messageId}');

  // Android/iOS auto-display the system notification whenever the payload
  // has a `notification` block, even without this handler running. Since the
  // server currently always includes that block, showing our own here too
  // would duplicate it. Only fall back to a manually-built local notification
  // for data-only messages (no `notification` block), e.g. on OEM devices
  // that suppress the OS auto-display via battery optimisation.
  if (message.notification != null) {
    AppLogger().d(
      '[FCM] Background message has a `notification` payload — skipping '
      'local notification to avoid duplicating the OS auto-display.',
    );
    return;
  }

  AppLogger().d(
    '[FCM] Background message is data-only — showing local notification fallback.',
  );

  final title =
      message.data['title'] as String? ??
      message.data['type'] as String? ??
      'Utility Bills';
  final body =
      message.data['body'] as String? ?? message.data['message'] as String? ?? '';

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: initSettings,
  );

  // Android 8+ requires the channel to exist before posting a notification.
  // The background isolate doesn't share state with the main isolate, so the
  // channel created in initLocalNotifications() is not available here.
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          importance: Importance.high,
        ),
      );

  await plugin.show(
    id: message.hashCode,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    ),
  );
}

const _androidChannelId = 'utility_bills_notifications';
const _androidChannelName = 'Utility Bills';

class NativeNotificationService
    with WidgetsBindingObserver
    implements NotificationService {
  static final NativeNotificationService _instance =
      NativeNotificationService._internal();

  factory NativeNotificationService() => _instance;

  NativeNotificationService._internal();

  final uuid = const Uuid();

  @override
  bool initialized = false;

  @override
  StreamSubscription<SseEvent>? sseEventsSubscription;

  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription? _tokenRefreshSubscription;

  GlobalKey<NavigatorState>? _navigatorKey;

  final _trackerHelper = BillNotificationTrackerHelper();

  @override
  Future<void> initialize() async {
    if (AppConfig.mode == AppMode.server) return;
    if (initialized) return;

    initialized = true;

    AppLogger().d('[NotificationService] Initializing...');

    try {
      await initLocalNotifications();
      await _initFcm();

      await connectSse(AppConfig.apiBaseUrl, await AppConfig.deviceId);
      WidgetsBinding.instance.addObserver(this);
      AppLogger().d('[NotificationService] Initialized successfully');
    } catch (e) {
      AppLogger().e(
        '[NotificationService] Initialization failed: $e',
        error: e,
      );
      initialized = false;
    }
  }

  @override
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  @override
  Future<void> handleLaunchNotification() async {
    final details = await _localNotifications.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTap(details?.notificationResponse?.payload);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenRefreshSubscription?.cancel();
    sseEventsSubscription?.cancel();
    SseService.instance.disconnect();
    initialized = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconnectSseIfNeeded();
    }
  }

  void _reconnectSseIfNeeded() async {
    if (SseService.instance.isConnected) return;
    AppLogger().d('[SSE] App resumed — force reconnecting');
    await SseService.instance.forceReconnect(
      AppConfig.apiBaseUrl,
      await AppConfig.deviceId,
    );
  }

  //region Local Notifications
  @override
  Future<void> initLocalNotifications() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      AppLogger().w(
        '[LocalNotifications] Skipping local notification initialization on Windows',
      );
      return;
    }

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response.payload);
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final impl =
          _localNotifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      if (impl != null) {
        await impl.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidChannelId,
            _androidChannelName,
            importance: Importance.high,
          ),
        );

        final permissionGranted = await impl.requestNotificationsPermission();
        if (permissionGranted != null && permissionGranted) {
          AppLogger().d('[LocalNotifications] Permission granted on Android');
        } else {
          AppLogger().w('[LocalNotifications] Permission denied on Android');
        }
      }
    }

    AppLogger().d('[LocalNotifications] Initialized');
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      AppLogger().w(
        '[LocalNotifications] Skipped showing notification: $title, on Windows',
      );
      return;
    }

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> cancelNotification(int id, {String? tag}) =>
      _localNotifications.cancel(id: id, tag: tag);

  @override
  Future<void> cancelAllNotifications() => _localNotifications.cancelAll();

  @override
  Future<void> cancelAllPendingNotifications() =>
      _localNotifications.cancelAllPendingNotifications();

  //endregion

  //region SSE
  @override
  Future<void> connectSse(String apiBaseUrl, String deviceId) async {
    await SseService.instance.connect(apiBaseUrl, deviceId);
    sseEventsSubscription = SseService.instance.events.listen(handleSseEvent);
  }

  @override
  void handleSseEvent(SseEvent event) {
    // Dispatch async work without blocking the SSE stream.
    unawaited(_handleSseEventAsync(event));
  }

  Future<void> _handleSseEventAsync(SseEvent event) async {
    try {
      final title = switch (event.type) {
        SseEventType.newBill => 'New Bill',
        SseEventType.newPayment => 'New Payment',
      };

      AppLogger().d('[SSE] ${event.type}: $title');
      await showNotification(title: title, body: event.message);
      addToStore(type: event.type, title: title, body: event.message);

      // Await the reload so bills/rentors are current before readiness check.
      await _reloadRepositoryAsync(event.type);

      if (event.type == SseEventType.newBill) {
        if (RentorsRepository().rentors.isEmpty) {
          await RentorsRepository().reload();
        }
        final allRentors = RentorsRepository().rentors;
        final allBills = BillsRepository().bills;

        final incomingBills = _parseBillsFromSseData(event.data, allBills);
        for (final bill in incomingBills) {
          final composeNotifications = await BillReadinessService()
              .checkReadiness(bill, allRentors, allBills);

          final now = DateTime.now();
          for (final cn in composeNotifications) {
            await _trackerHelper.logComposeNotificationSent(
              rentorId: cn.rentor.rentorId,
              month: now.month,
              year: now.year,
              billGroup: cn.isWater ? 'water' : 'regular',
            );
            await _showComposeNotification(cn);
          }
        }
      }
    } catch (e) {
      AppLogger().e('[NotificationService] SSE handling error: $e', error: e);
    }
  }

  Future<void> _reloadRepositoryAsync(SseEventType type) async {
    switch (type) {
      case SseEventType.newBill:
        await BillsRepository().reload();
      case SseEventType.newPayment:
        await PaymentsRepository().reload();
    }
  }

  //endregion

  Future<void> _showComposeNotification(ComposeNotification cn) async {
    if (defaultTargetPlatform == TargetPlatform.windows) return;

    final firstName = cn.rentor.name.split(' ').first;
    final title =
        cn.isWater
            ? 'Water bill ready for $firstName'
            : 'Compose bill summary for $firstName';
    final body =
        cn.isWater
            ? 'Tap to compose water bill message'
            : 'All bills received — tap to generate message';
    final payload = jsonEncode({
      'rentorId': cn.rentor.rentorId,
      'billIds': cn.bills.map((b) => b.billId).toList(),
      'isWater': cn.isWater,
    });

    await _localNotifications.show(
      id: cn.rentor.rentorId.hashCode ^ (cn.isWater ? 1 : 0),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> _handleNotificationTap(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final rentorId = data['rentorId'] as String;
      final billIds = (data['billIds'] as List).cast<String>();

      if (RentorsRepository().rentors.isEmpty) {
        await RentorsRepository().reload();
      }
      final rentor = RentorsRepository().rentors.cast<Rentor?>().firstWhere(
        (r) => r?.rentorId == rentorId,
        orElse: () => null,
      );
      if (rentor == null) return;

      if (BillsRepository().bills.isEmpty) {
        await BillsRepository().reload();
      }
      final bills =
          BillsRepository().bills
              .where((b) => billIds.contains(b.billId))
              .toList();
      if (bills.isEmpty) return;

      final message = BillSummaryService().generateMessage(rentor, bills);

      _navigatorKey?.currentState?.push(
        MaterialPageRoute(
          builder: (_) => MessagePreviewScreen(initialMessage: message),
        ),
      );
    } catch (e) {
      AppLogger().e('[NotificationService] Tap handling error: $e', error: e);
    }
  }

  /// Returns the [Bill] objects described by this SSE [data] map.
  ///
  /// The server sends two shapes:
  /// - **Individual** (`< 5` bills): `data` contains the full bill JSON with a
  ///   `'billId'` key → parsed directly via [Bill.fromJson].
  /// - **Grouped** (`≥ 5` bills): `data` contains only `{'billIds': [...]}` →
  ///   each ID is looked up in [allBills] (already reloaded from the server).
  List<Bill> _parseBillsFromSseData(
    Map<String, dynamic> data,
    List<Bill> allBills,
  ) {
    if (data.containsKey('billId')) {
      return [Bill.fromJson(data)];
    } else if (data.containsKey('billIds')) {
      final ids = (data['billIds'] as List).cast<String>();
      return allBills.where((b) => ids.contains(b.billId)).toList();
    }
    return [];
  }

  //region FCM
  Future<void> _initFcm() async {
    final supported =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (!supported) {
      AppLogger().d('[FCM] Skipping — not supported on this platform');
      return;
    }

    // Re-enabled now that _firebaseMessagingBackgroundHandler guards against
    // duplicating the OS auto-displayed notification (see its `notification
    // != null` check above).
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    AppLogger().d('[FCM] Background message handler registered');

    final settings = await FirebaseMessaging.instance.requestPermission();
    AppLogger().d('[FCM] Permission: ${settings.authorizationStatus}');

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerFcmToken(token);

    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen(_registerFcmToken);

    FirebaseMessaging.onMessage.listen(_handleFcmForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmOpen);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleFcmOpen(initial);
  }

  Future<void> _registerFcmToken(String token) async {
    final deviceId = await AppConfig.deviceId;
    AppLogger().d('[FCM] Registering token for device $deviceId');
    await ApiService.notifications().registerDeviceToken(deviceId, token);
  }

  void _handleFcmForeground(RemoteMessage message) {
    // Only act as a fallback when SSE is not connected.
    if (SseService.instance.isConnected) return;

    AppLogger().d('[FCM] Foreground fallback: ${message.notification?.title}');
    final eventType = _eventTypeFromString(message.data['type']);
    if (eventType == null) return;

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    showNotification(title: title, body: body);
    addToStore(type: eventType, title: title, body: body);
    reloadRepository(eventType);
  }

  void _handleFcmOpen(RemoteMessage message) {
    AppLogger().d('[FCM] Opened from notification: ${message.data}');
    final eventType = _eventTypeFromString(message.data['type']);
    if (eventType == null) return;
    addToStore(
      type: eventType,
      title: message.notification?.title ?? '',
      body: message.notification?.body ?? '',
    );
    reloadRepository(eventType);
  }

  SseEventType? _eventTypeFromString(String? type) => switch (type) {
    'newBill' => SseEventType.newBill,
    'newPayment' => SseEventType.newPayment,
    _ => null,
  };

  //endregion

  //region Store & repository helpers
  @override
  void addToStore({
    required SseEventType type,
    required String title,
    required String body,
  }) {
    AppNotificationStore().add(
      AppNotification(
        id: uuid.v4(),
        type: type,
        title: title,
        body: body,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void reloadRepository(SseEventType type) {
    switch (type) {
      case SseEventType.newBill:
        BillsRepository().reload();
      case SseEventType.newPayment:
        PaymentsRepository().reload();
    }
  }

  //endregion
}
