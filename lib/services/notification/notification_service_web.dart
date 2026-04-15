import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:web/web.dart' as web;

import 'sse_service.dart';
import 'notification_service_base.dart';
import '../../config/app_config.dart';
import '../../data/models/sse_event.dart';
import '../../services/api/api_service.dart';
import '../../utils/app_logger.dart';

/// Concrete [NotificationServiceBase] for Flutter Web.
class NotificationService extends NotificationServiceBase {
  static final NotificationService _instance =
  NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  StreamSubscription? _tokenRefreshSubscription;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> initialize() async {
    if (initialized) return;
    if (AppConfig.mode == AppMode.server) return;
    initialized = true;

    await _requestWebPermission();
    await _initFcm();
    await connectSse(AppConfig.apiBaseUrl, await AppConfig.deviceId);
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Web Notification API
  // ---------------------------------------------------------------------------

  Future<void> _requestWebPermission() async {
    if (web.Notification.permission == 'default') {
      await web.Notification.requestPermission().toDart;
    }
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (web.Notification.permission != 'granted') return;
    web.Notification(title, web.NotificationOptions(body: body));
  }

  // ---------------------------------------------------------------------------
  // FCM (web uses VAPID key)
  // ---------------------------------------------------------------------------

  Future<void> _initFcm() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await FirebaseMessaging.instance.requestPermission();
    AppLogger().d('[FCM] Permission: ${settings.authorizationStatus}');

    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: await AppConfig.firebaseWebPushPublicKey,
    );
    if (token != null) await _registerFcmToken(token);

    _tokenRefreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen(_registerFcmToken);

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
  }

  SseEventType? _eventTypeFromString(String? type) => switch (type) {
    'newBill' => SseEventType.newBill,
    'newPayment' => SseEventType.newPayment,
    _ => null,
  };
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger().d('[FCM] Background message: ${message.messageId}');
}