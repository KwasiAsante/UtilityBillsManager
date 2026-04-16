import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import 'app_notification_store.dart';
import 'notification_service.dart';
import 'sse_service_native.dart';
import '../../data/models/app_notification.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../utils/app_logger.dart';
import '../../config/app_config.dart';
import '../../data/models/sse_event.dart';

class WindowsNotificationService implements NotificationService {
  static final WindowsNotificationService _instance = WindowsNotificationService._internal();

  factory WindowsNotificationService() => _instance;

  WindowsNotificationService._internal();

  final uuid = const Uuid();

  @override
  bool initialized = false;

  @override
  StreamSubscription<SseEvent>? sseEventsSubscription;

  final _localNotifications = FlutterLocalNotificationsPlugin();

  //region Lifecycle
  @override
  Future<void> initialize() async {
    if (AppConfig.mode == AppMode.server) return;
    if (initialized) return;

    initialized = true;

    AppLogger().d('[NotificationService](Windows) Initializing...');

    try {
      await initLocalNotifications();
      await connectSse(AppConfig.apiBaseUrl, await AppConfig.deviceId);
      AppLogger().d('[NotificationService](Windows) Initialized successfully');
    } catch (e) {
      AppLogger().e('[NotificationService](Windows) Initialization failed: $e', error: e);
      initialized = false;
    }
  }

  @override
  void dispose() {
    sseEventsSubscription?.cancel();
    SseService.instance.disconnect();
    initialized = false;
  }
  //endregion

  //region Local Notifications
  @override
  Future<void> initLocalNotifications() async {
    const initSettings = InitializationSettings(
      windows: WindowsInitializationSettings(
        appName: 'Utility Bills Manager',
        appUserModelId: 'com.asante.UtilityBillsManager',
        guid: 'a3f1d2c4-8b7e-4f6a-9c2d-1e5b0a3f8d7c',
      ),
    );

    await _localNotifications.initialize(settings: initSettings);
    AppLogger().d('[LocalNotifications] Windows initialised');
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
        windows: WindowsNotificationDetails(),
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