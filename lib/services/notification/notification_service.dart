import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/sse_event.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../services/api/api_service.dart';
import '../../utils/app_logger.dart';
import 'app_notification_store.dart';
import 'sse_service.dart';

/// Whether FCM is supported on the current platform.
///
/// FCM is available on Android, iOS, macOS, and Web.
/// Windows and Linux are not supported by the firebase_messaging package.
bool get _fcmSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Whether flutter_local_notifications is supported on the current platform.
///
/// Supports Android, iOS, macOS, Windows, and Linux — not Web.
bool get _localNotificationsSupported => !kIsWeb;

/// Top-level FCM background message handler (separate isolate).
///
/// Firebase displays the notification automatically; the handler only logs.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger().d('[FCM] Background message: ${message.messageId}');
}

const _androidChannelId = 'utility_bills_notifications';
const _androidChannelName = 'Utility Bills';

/// Singleton that orchestrates SSE and FCM for client mode.
///
/// Startup sequence (called once from [main]):
///   1. [initialize] — guards against server mode and double-init.
///   2. [_initLocalNotifications] — sets up flutter_local_notifications.
///   3. [_initFcm] — requests permission, registers token, sets up handlers.
///   4. [_connectSse] — opens the SSE stream and subscribes to events.
///
/// When the server pushes a [SseEvent]:
///   • A system notification is shown via flutter_local_notifications.
///   • An [AppNotification] is added to [AppNotificationStore].
///   • The relevant repository ([BillsRepository] / [PaymentsRepository])
///     is reloaded, which notifies listening screens via [ChangeNotifier].
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _uuid = const Uuid();

  StreamSubscription? _tokenRefreshSubscription;
  StreamSubscription<SseEvent>? _sseEventsSubscription;
  bool _initialized = false;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;
    if (AppConfig.mode == AppMode.server) return;

    _initialized = true;

    if (_localNotificationsSupported) {
      await _initLocalNotifications();
    }

    if (_fcmSupported) {
      await _initFcm();
    } else {
      AppLogger().d('[FCM] Skipping — not supported on this platform');
    }

    _connectSse();
  }

  // ---------------------------------------------------------------------------
  // Local notifications
  // ---------------------------------------------------------------------------

  Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(
        defaultActionName: 'Open',
      ),
      windows: WindowsInitializationSettings(
        appName: 'Utility Bills Manager',
        appUserModelId: 'com.example.UtilityBillsManager',
        guid: 'a3f1d2c4-8b7e-4f6a-9c2d-1e5b0a3f8d7c',
      ),
    );

    await _localNotifications.initialize(settings: initSettings);

    // Create the Android notification channel.
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidChannelId,
            _androidChannelName,
            importance: Importance.high,
          ),
        );

    AppLogger().d('[LocalNotifications] Initialised');
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (!_localNotificationsSupported) return;

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF, // int-safe id
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

  // ---------------------------------------------------------------------------
  // FCM
  // ---------------------------------------------------------------------------

  Future<void> _initFcm() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await FirebaseMessaging.instance.requestPermission();
    AppLogger().d('[FCM] Permission: ${settings.authorizationStatus}');

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerFcmToken(token);

    _tokenRefreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen(_registerFcmToken);

    // Foreground FCM: the SSE event already handled the reload and
    // notification, so we only log here to avoid duplicates.
    FirebaseMessaging.onMessage.listen((msg) {
      AppLogger().d(
        '[FCM] Foreground: ${msg.notification?.title} — ${msg.notification?.body}',
      );
    });

    // Notification tap from background state.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmOpen);

    // Notification tap from terminated state.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleFcmOpen(initial);
  }

  Future<void> _registerFcmToken(String token) async {
    AppLogger().d('[FCM] Registering token for device ${AppConfig.deviceId}');
    await ApiService.notifications()
        .registerDeviceToken(AppConfig.deviceId, token);
  }

  void _handleFcmOpen(RemoteMessage message) {
    AppLogger().d('[FCM] Opened from notification: ${message.data}');
    // Add to in-app store so the user sees it even if the SSE event was missed.
    final type = message.data['type'];
    if (type == 'newBill' || type == 'newPayment') {
      _addToStore(
        type: type == 'newBill' ? SseEventType.newBill : SseEventType.newPayment,
        title: message.notification?.title ?? '',
        body: message.notification?.body ?? '',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SSE
  // ---------------------------------------------------------------------------

  void _connectSse() {
    SseService.instance.connect(AppConfig.apiBaseUrl, AppConfig.deviceId);
    _sseEventsSubscription =
        SseService.instance.events.listen(_handleSseEvent);
  }

  void _handleSseEvent(SseEvent event) {
    final title = switch (event.type) {
      SseEventType.newBill => 'New Bill',
      SseEventType.newPayment => 'New Payment',
    };

    _showLocalNotification(title: title, body: event.message);
    _addToStore(type: event.type, title: title, body: event.message);

    switch (event.type) {
      case SseEventType.newBill:
        BillsRepository().reload();
      case SseEventType.newPayment:
        PaymentsRepository().reload();
    }
  }

  void _addToStore({
    required SseEventType type,
    required String title,
    required String body,
  }) {
    AppNotificationStore().add(AppNotification(
      id: _uuid.v4(),
      type: type,
      title: title,
      body: body,
      timestamp: DateTime.now(),
    ));
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _sseEventsSubscription?.cancel();
    SseService.instance.disconnect();
    _initialized = false;
  }
}
