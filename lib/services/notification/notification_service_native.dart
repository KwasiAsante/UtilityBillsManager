import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'sse_service.dart';
import 'notification_service_base.dart';
import '../../config/app_config.dart';
import '../../data/models/sse_event.dart';
import '../../services/api/api_service.dart';
import '../../utils/app_logger.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger().d('[FCM] Background message: ${message.messageId}');
}

const _androidChannelId = 'utility_bills_notifications';
const _androidChannelName = 'Utility Bills';

/// Concrete [NotificationServiceBase] for Android, iOS, macOS, Windows, Linux.
class NotificationService extends NotificationServiceBase {
  static final NotificationService _instance =
  NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription? _tokenRefreshSubscription;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> initialize() async {
    if (initialized) return;
    if (AppConfig.mode == AppMode.server) return;
    initialized = true;

    await _initLocalNotifications();
    await _initFcm();
    await connectSse(AppConfig.apiBaseUrl, await AppConfig.deviceId);
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    super.dispose();
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

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
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
    final supported = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (!supported) {
      AppLogger().d('[FCM] Skipping — not supported on this platform');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await FirebaseMessaging.instance.requestPermission();
    AppLogger().d('[FCM] Permission: ${settings.authorizationStatus}');

    final token = await FirebaseMessaging.instance.getToken();
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
  }

  SseEventType? _eventTypeFromString(String? type) => switch (type) {
    'newBill' => SseEventType.newBill,
    'newPayment' => SseEventType.newPayment,
    _ => null,
  };
}