import '../../services/notification/notification_service.dart';
import '../../services/notification/notification_service_web.dart';

/// Returns the web [NotificationService] implementation.
/// Called only when compiled for the web target.
NotificationService createNotificationService() => WebNotificationService();