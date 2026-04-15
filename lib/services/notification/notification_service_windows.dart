import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service_base.dart';
import '../../config/app_config.dart';
import '../../utils/app_logger.dart';

/// Concrete [NotificationServiceBase] for Windows.
///
/// Windows does not support FCM. Notifications are delivered exclusively
/// via [flutter_local_notifications] (WinRT toast API) and SSE.
class NotificationService extends NotificationServiceBase {
  static final NotificationService _instance =
  NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _localNotifications = FlutterLocalNotificationsPlugin();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> initialize() async {
    if (initialized) return;
    if (AppConfig.mode == AppMode.server) return;
    initialized = true;

    await _initLocalNotifications();
    await connectSse(AppConfig.apiBaseUrl, await AppConfig.deviceId);
  }

  // ---------------------------------------------------------------------------
  // Local notifications (WinRT toast)
  // ---------------------------------------------------------------------------

  Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      windows: WindowsInitializationSettings(
        appName: 'Utility Bills Manager',
        appUserModelId: 'com.example.UtilityBillsManager',
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
}