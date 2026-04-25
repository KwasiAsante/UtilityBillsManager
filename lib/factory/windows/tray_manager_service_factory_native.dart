import 'package:flutter/foundation.dart';
import 'package:utility_bills_manager/factory/windows/tray_manager_service_factory.dart';
import 'package:utility_bills_manager/utils/app_logger.dart';

Future<void> initTrayManager() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      await TrayManagerService().init();
      return;
    default:
      AppLogger().w(
        'Platform "${defaultTargetPlatform.name}" is not supported.',
      );
      return;
  }
}