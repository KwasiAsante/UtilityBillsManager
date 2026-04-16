import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import 'app_notification_store.dart';
import 'sse_service_native.dart';
import '../api/api_service.dart';
import '../../config/app_config.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/sse_event.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../services/notification/notification_service.dart';
import '../../utils/app_logger.dart';
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger().d('[FCM] Background message: ${message.messageId}');
}

const _androidChannelId = 'utility_bills_notifications';
const _androidChannelName = 'Utility Bills';

class NativeNotificationService implements NotificationService {
  static final NativeNotificationService _instance = NativeNotificationService._internal();

  factory NativeNotificationService() => _instance;

  NativeNotificationService._internal();

  final uuid = const Uuid();

  @override
  bool initialized = false;

  @override
  StreamSubscription<SseEvent>? sseEventsSubscription;

  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription? _tokenRefreshSubscription;

  @override
  Future<void> initialize() async {
    if (AppConfig.mode == AppMode.server) return;
    if (initialized) return;

    initialized = true;

    AppLogger().d('[NotificationService]W Initializing...');

    try {
      await initLocalNotifications();
      await _initFcm();

      await connectSse(AppConfig.apiBaseUrl, await AppConfig.deviceId);
      AppLogger().d('[NotificationService] Initialized successfully');
    } catch (e) {
      AppLogger().e('[NotificationService] Initialization failed: $e', error: e);
      initialized = false;
    }
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    sseEventsSubscription?.cancel();
    SseService.instance.disconnect();
    initialized = false;
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

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    );

    await _localNotifications.initialize(settings: initSettings);

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
      id: DateTime
          .now()
          .millisecondsSinceEpoch & 0x7FFFFFFF,
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
    final title = switch (event.type) {
      SseEventType.newBill => 'New Bill',
      SseEventType.newPayment => 'New Payment',
    };

    AppLogger().d('[SSE] ${event.type}: $title');
    showNotification(title: title, body: event.message);
    addToStore(type: event.type, title: title, body: event.message);
    reloadRepository(event.type);
  }

  //endregion

  //region FCM
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

  SseEventType? _eventTypeFromString(String? type) =>
      switch (type) {
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

// import 'dart:async';
//
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
//
// import 'sse_service.dart';
// import 'notification_service_base.dart';
// import '../../config/app_config.dart';
// import '../../data/models/sse_event.dart';
// import '../../services/api/api_service.dart';
// import '../../utils/app_logger.dart';
//
// @pragma('vm:entry-point')
// Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   AppLogger().d('[FCM] Background message: ${message.messageId}');
// }
//
// const _androidChannelId = 'utility_bills_notifications';
// const _androidChannelName = 'Utility Bills';
//
// /// Concrete [NotificationServiceBase] for Android, iOS, and macOS.
// ///
// /// This file is also the fallback for Windows and Linux when
// /// `--dart-define=BUILD_TARGET=windows` is not passed at build time.
// /// Both of those platforms skip local-notification and FCM init to avoid
// /// crashes — only SSE runs on them via this file.
// class NotificationService extends NotificationServiceBase {
//   static final NotificationService _instance =
//   NotificationService._internal();
//   factory NotificationService() => _instance;
//   NotificationService._internal();
//
//   final _localNotifications = FlutterLocalNotificationsPlugin();
//   StreamSubscription? _tokenRefreshSubscription;
//
//   // ---------------------------------------------------------------------------
//   // Lifecycle
//   // ---------------------------------------------------------------------------
//
//   @override
//   Future<void> initialize() async {
//     if (initialized) return;
//     if (AppConfig.mode == AppMode.server) return;
//     initialized = true;
//
//     // Windows and Linux skip local-notification and FCM init:
//     // - Windows: flutter_local_notifications_windows is a separate package
//     //   handled by notification_service_windows.dart. If this file is reached
//     //   on Windows (missing --dart-define=BUILD_TARGET=windows), initialising
//     //   the wrong plugin would crash.
//     // - Linux: no Firebase config and no notification daemon is guaranteed.
//     // SSE still connects on both platforms.
//     final isDesktopFallback = defaultTargetPlatform == TargetPlatform.linux ||
//         defaultTargetPlatform == TargetPlatform.windows;
//     if (!isDesktopFallback) {
//       await _initLocalNotifications();
//       await _initFcm();
//     }
//     await connectSse(AppConfig.apiBaseUrl, await AppConfig.deviceId);
//   }
//
//   @override
//   void dispose() {
//     _tokenRefreshSubscription?.cancel();
//     super.dispose();
//   }
//
//   // ---------------------------------------------------------------------------
//   // Local notifications
//   // ---------------------------------------------------------------------------
//
//   Future<void> _initLocalNotifications() async {
//     const initSettings = InitializationSettings(
//       android: AndroidInitializationSettings('@mipmap/ic_launcher'),
//       iOS: DarwinInitializationSettings(),
//       macOS: DarwinInitializationSettings(),
//       linux: LinuxInitializationSettings(defaultActionName: 'Open'),
//     );
//
//     await _localNotifications.initialize(settings: initSettings);
//
//     await _localNotifications
//         .resolvePlatformSpecificImplementation<
//         AndroidFlutterLocalNotificationsPlugin>()
//         ?.createNotificationChannel(
//       const AndroidNotificationChannel(
//         _androidChannelId,
//         _androidChannelName,
//         importance: Importance.high,
//       ),
//     );
//
//     AppLogger().d('[LocalNotifications] Initialised');
//   }
//
//   @override
//   Future<void> showNotification({
//     required String title,
//     required String body,
//   }) async {
//     if (defaultTargetPlatform == TargetPlatform.linux ||
//         defaultTargetPlatform == TargetPlatform.windows) {
//       // Local notifications are skipped on Windows/Linux (no init was performed).
//       AppLogger().d('[LocalNotifications] Skipped on ${defaultTargetPlatform.name}: $title');
//       return;
//     }
//
//     await _localNotifications.show(
//       id: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
//       title: title,
//       body: body,
//       notificationDetails: const NotificationDetails(
//         android: AndroidNotificationDetails(
//           _androidChannelId,
//           _androidChannelName,
//           importance: Importance.high,
//           priority: Priority.high,
//         ),
//         iOS: DarwinNotificationDetails(),
//         macOS: DarwinNotificationDetails(),
//       ),
//     );
//   }
//
//   // ---------------------------------------------------------------------------
//   // FCM
//   // ---------------------------------------------------------------------------
//
//   Future<void> _initFcm() async {
//     final supported = defaultTargetPlatform == TargetPlatform.android ||
//         defaultTargetPlatform == TargetPlatform.iOS ||
//         defaultTargetPlatform == TargetPlatform.macOS;
//
//     if (!supported) {
//       AppLogger().d('[FCM] Skipping — not supported on this platform');
//       return;
//     }
//
//     FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
//
//     final settings = await FirebaseMessaging.instance.requestPermission();
//     AppLogger().d('[FCM] Permission: ${settings.authorizationStatus}');
//
//     final token = await FirebaseMessaging.instance.getToken();
//     if (token != null) await _registerFcmToken(token);
//
//     _tokenRefreshSubscription =
//         FirebaseMessaging.instance.onTokenRefresh.listen(_registerFcmToken);
//
//     FirebaseMessaging.onMessage.listen(_handleFcmForeground);
//     FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmOpen);
//
//     final initial = await FirebaseMessaging.instance.getInitialMessage();
//     if (initial != null) _handleFcmOpen(initial);
//   }
//
//   Future<void> _registerFcmToken(String token) async {
//     final deviceId = await AppConfig.deviceId;
//     AppLogger().d('[FCM] Registering token for device $deviceId');
//     await ApiService.notifications().registerDeviceToken(deviceId, token);
//   }
//
//   void _handleFcmForeground(RemoteMessage message) {
//     // Only act as a fallback when SSE is not connected.
//     if (SseService.instance.isConnected) return;
//
//     AppLogger().d('[FCM] Foreground fallback: ${message.notification?.title}');
//     final eventType = _eventTypeFromString(message.data['type']);
//     if (eventType == null) return;
//
//     final title = message.notification?.title ?? '';
//     final body = message.notification?.body ?? '';
//     showNotification(title: title, body: body);
//     addToStore(type: eventType, title: title, body: body);
//     reloadRepository(eventType);
//   }
//
//   void _handleFcmOpen(RemoteMessage message) {
//     AppLogger().d('[FCM] Opened from notification: ${message.data}');
//     final eventType = _eventTypeFromString(message.data['type']);
//     if (eventType == null) return;
//     addToStore(
//       type: eventType,
//       title: message.notification?.title ?? '',
//       body: message.notification?.body ?? '',
//     );
//   }
//
//   SseEventType? _eventTypeFromString(String? type) => switch (type) {
//     'newBill' => SseEventType.newBill,
//     'newPayment' => SseEventType.newPayment,
//     _ => null,
//   };
// }

