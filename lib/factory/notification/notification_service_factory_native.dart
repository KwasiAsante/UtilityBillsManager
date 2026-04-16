import 'package:flutter/foundation.dart';

import '../../services/notification/notification_service.dart';
import '../../services/notification/notification_service_native.dart';
import '../../services/notification/notification_service_windows.dart';

/// All platform-specific configuration is built here and injected into
/// [NativeNotificationService]. This is the only place in the codebase
/// that branches on [defaultTargetPlatform].
NotificationService createNotificationService() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return NativeNotificationService();
    case TargetPlatform.windows:
      return WindowsNotificationService();
    default:
      throw UnsupportedError(
        'Platform "${defaultTargetPlatform.name}" is not supported.',
      );
  }
}
