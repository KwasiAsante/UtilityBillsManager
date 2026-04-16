/// Resolves the correct [NotificationService] for the current platform using
/// Dart's conditional imports. This is the only file in the codebase that
/// knows about platform branching.
///
/// Usage:
/// ```dart
/// import 'notifications/notification_service_factory.dart';
///
/// final service = createNotificationService();
/// await service.initialize(onTap: (payload) => handleTap(payload));
/// ```
library;

export '../../services/notification/notification_service.dart';

// Conditional imports — Dart picks exactly one at compile time.
// The stub (unsupported_notification_service.dart) is the fallback.
export 'notification_service_factory_native.dart'
if (dart.library.js_interop) 'notification_service_factory_web.dart';