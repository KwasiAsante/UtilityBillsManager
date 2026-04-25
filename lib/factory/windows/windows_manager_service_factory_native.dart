import 'package:flutter/foundation.dart';
import 'package:utility_bills_manager/services/windows/windows_manager_service.dart';
import 'package:utility_bills_manager/utils/app_logger.dart';

Future<void> initWindowManager() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      await WindowsManagerService.initWindowManager();
      return;
    default:
      AppLogger().w(
        'Platform "${defaultTargetPlatform.name}" is not supported.',
      );
      return;
  }
}