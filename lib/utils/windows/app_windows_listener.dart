import 'dart:io';
import 'package:window_manager/window_manager.dart';

class AppWindowListener extends WindowListener {
  final bool minimizeToTray; // true = minimize, false = close to tray

  AppWindowListener({this.minimizeToTray = true});

  @override
  void onWindowMinimize() async {
    if (!Platform.isWindows) return;
    if (minimizeToTray) {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    }
  }

  @override
  void onWindowClose() async {
    if (!Platform.isWindows) return;
    // Intercept close → hide to tray instead of quitting
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }
}