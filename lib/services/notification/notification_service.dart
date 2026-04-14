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
import '_notification_web_stub.dart'
    if (dart.library.js_interop) '_notification_web.dart';

bool get _fcmSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

bool get _localNotificationsSupported => !kIsWeb;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger().d('[FCM] Background message: ${message.messageId}');
}

const _androidChannelId = 'utility_bills_notifications';
const _androidChannelName = 'Utility Bills';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _uuid = const Uuid();

  StreamSubscription? _tokenRefreshSubscription;
  StreamSubscription<SseEvent>? _sseEventsSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (AppConfig.mode == AppMode.server) return;

    _initialized = true;

    if (_localNotificationsSupported) {
      await _initLocalNotifications();
    }

    if (kIsWeb) {
      await requestWebNotificationPermission();
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
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: WindowsInitializationSettings(
        appName: 'Utility Bills Manager',
        appUserModelId: 'com.example.UtilityBillsManager',
        guid: 'a3f1d2c4-8b7e-4f6a-9c2d-1e5b0a3f8d7c',
      ),
    );

    await _localNotifications.initialize(settings: initSettings);

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

  Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) {
      showWebNotification(title: title, body: body);
      return;
    }
    await _showLocalNotification(title: title, body: body);
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (!_localNotificationsSupported) return;

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

  // ---------------------------------------------------------------------------
  // FCM
  // ---------------------------------------------------------------------------

  Future<void> _initFcm() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await FirebaseMessaging.instance.requestPermission();
    AppLogger().d('[FCM] Permission: ${settings.authorizationStatus}');

    final token = kIsWeb
        ? await FirebaseMessaging.instance.getToken(
            vapidKey: await AppConfig.firebaseWebPushPublicKey)
        : await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerFcmToken(token);

    _tokenRefreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen(_registerFcmToken);

    // SSE handles foreground events; FCM foreground is a fallback.
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
    // Only act if SSE is not connected (avoid duplicate notifications).
    if (SseService.instance.isConnected) return;

    AppLogger().d('[FCM] Foreground fallback: ${message.notification?.title}');
    final type = message.data['type'];
    final eventType = switch (type) {
      'newBill' => SseEventType.newBill,
      'newPayment' => SseEventType.newPayment,
      _ => null,
    };
    if (eventType == null) return;

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    _showNotification(title: title, body: body);
    _addToStore(type: eventType, title: title, body: body);

    switch (eventType) {
      case SseEventType.newBill:
        BillsRepository().reload();
      case SseEventType.newPayment:
        PaymentsRepository().reload();
    }
  }

  void _handleFcmOpen(RemoteMessage message) {
    AppLogger().d('[FCM] Opened from notification: ${message.data}');
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

  void _connectSse() async {
    final deviceId = await AppConfig.deviceId;
    await SseService.instance.connect(AppConfig.apiBaseUrl, deviceId);
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
