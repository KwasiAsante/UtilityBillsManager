import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'app_notification_store.dart';
import 'notification_service.dart';
import 'sse_service_native.dart';
import '../bill_readiness/bill_readiness_service.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/bill.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../data/repositories/rentors_repository.dart';
import '../../helpers/bill_readiness/bill_notification_tracker_helper.dart';
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
  final _trackerHelper = BillNotificationTrackerHelper();

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

  @override
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    // Not supported on web — web uses browser URL navigation.
  }

  @override
  Future<void> handleLaunchNotification() async {
    // Not supported on web.
  }

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
      AppLogger().e('[NotificationService](Windows) SSE handling error: $e', error: e);
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
    final firstName = cn.rentor.name.split(' ').first;
    final title = cn.isWater
        ? 'Water bill ready for $firstName'
        : 'Compose bill summary for $firstName';
    final body = cn.isWater
        ? 'Tap to compose water bill message'
        : 'All bills received — open app to generate message';

    await _localNotifications.show(
      id: cn.rentor.rentorId.hashCode ^ (cn.isWater ? 1 : 0),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  List<Bill> _parseBillsFromSseData(
      Map<String, dynamic> data, List<Bill> allBills) {
    if (data.containsKey('billId')) {
      return [Bill.fromJson(data)];
    } else if (data.containsKey('billIds')) {
      final ids = (data['billIds'] as List).cast<String>();
      return allBills.where((b) => ids.contains(b.billId)).toList();
    }
    return [];
  }

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