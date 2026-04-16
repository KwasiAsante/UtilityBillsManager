import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import '../api/api_service.dart';
import 'app_notification_store.dart';
import 'notification_service.dart';
import 'sse_service_native.dart';
import '../../config/app_config.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/sse_event.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../utils/app_logger.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger().d('[FCM] Background message: ${message.messageId}');
}

class WebNotificationService implements NotificationService {
  static final WebNotificationService _instance = WebNotificationService._internal();

  factory WebNotificationService() => _instance;

  WebNotificationService._internal();

  final uuid = const Uuid();

  @override
  bool initialized = false;

  @override
  StreamSubscription<SseEvent>? sseEventsSubscription;

  StreamSubscription? _tokenRefreshSubscription;

  List<web.Notification> activeNotifications = [];

  //region Lifecycle
  @override
  Future<void> initialize() async {
    if (AppConfig.mode == AppMode.server) return;
    if (initialized) return;

    AppLogger().d('[NotificationService](Web) Initializing...');

    initialized = true;

    try {
      await initLocalNotifications();
      await _initFcm();
      await connectSse(AppConfig.apiBaseUrl, await AppConfig.deviceId);
      AppLogger().d('[NotificationService](Web) Initialized successfully');
    } catch (e) {
      AppLogger().e('[NotificationService](Web) Initialization failed: $e', error: e);
      initialized = false;
    }
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    sseEventsSubscription?.cancel();
    SseService.instance.disconnect();
    if (activeNotifications.isNotEmpty) {
      for (var n in activeNotifications) {
        n.close();
      }
      activeNotifications.clear();
    }
    initialized = false;
  }
  //endregion

  //region Local Notifications
  Future<void> requestNotificationPermissions() async {
    if (web.Notification.permission == 'default') {
      await web.Notification.requestPermission().toDart;
    }
  }

  @override
  Future<void> initLocalNotifications() async {
    await requestNotificationPermissions();

    AppLogger().d('[LocalNotifications] Web initialised');
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? tag,
  }) async {
    if (web.Notification.permission != 'granted') return;
    final notification = web.Notification(title, web.NotificationOptions(tag: tag ??  Uuid().v4(), body: body));
    activeNotifications.add(notification);
  }

  @override
  Future<void> cancelNotification(int id, {String? tag}) async {
    if (tag != null) {
      activeNotifications.where((n) => n.tag == tag).forEach((n) => n.close());
      activeNotifications.removeWhere((n) => n.tag == tag);
    }
  }

  @override
  Future<void> cancelAllNotifications() async {
    if (activeNotifications.isEmpty) return;
    for (var n in activeNotifications) {
      n.close();
    }
    activeNotifications.clear();

  }

  @override
  Future<void> cancelAllPendingNotifications() async {}
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

//region FCM
  Future<void> _initFcm() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await FirebaseMessaging.instance.requestPermission();
    AppLogger().d('[FCM] Permission: ${settings.authorizationStatus}');

    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: await AppConfig.firebaseWebPushPublicKey,
    );
    if (token != null) await _registerFcmToken(token);

    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(_registerFcmToken);

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
//endregion
}

// import 'dart:async';
// import 'dart:js_interop';
//
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:web/web.dart' as web;
//
// import 'sse_service.dart';
// import 'notification_service_base.dart';
// import '../../config/app_config.dart';
// import '../../data/models/sse_event.dart';
// import '../../services/api/api_service.dart';
// import '../../utils/app_logger.dart';
//
// /// Concrete [NotificationServiceBase] for Flutter Web.
// class NotificationService extends NotificationServiceBase {
//   static final NotificationService _instance =
//   NotificationService._internal();
//   factory NotificationService() => _instance;
//   NotificationService._internal();
//
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
//     await _requestWebPermission();
//     await _initFcm();
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
//   // Web Notification API
//   // ---------------------------------------------------------------------------
//
//   Future<void> _requestWebPermission() async {
//     if (web.Notification.permission == 'default') {
//       await web.Notification.requestPermission().toDart;
//     }
//   }
//
//   @override
//   Future<void> showNotification({
//     required String title,
//     required String body,
//   }) async {
//     if (web.Notification.permission != 'granted') return;
//     web.Notification(title, web.NotificationOptions(body: body));
//   }
//
//   // ---------------------------------------------------------------------------
//   // FCM (web uses VAPID key)
//   // ---------------------------------------------------------------------------
//
//   Future<void> _initFcm() async {
//     FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
//
//     final settings = await FirebaseMessaging.instance.requestPermission();
//     AppLogger().d('[FCM] Permission: ${settings.authorizationStatus}');
//
//     final token = await FirebaseMessaging.instance.getToken(
//       vapidKey: await AppConfig.firebaseWebPushPublicKey,
//     );
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
//
// @pragma('vm:entry-point')
// Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   AppLogger().d('[FCM] Background message: ${message.messageId}');
// }
