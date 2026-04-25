import 'package:window_manager/window_manager.dart';

import '../../utils/windows/app_windows_listener.dart';

class WindowsManagerService {
  static Future<void> initWindowManager() async {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      center: true,
      skipTaskbar: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // Prevent default close behavior so we can intercept it
    await windowManager.setPreventClose(true);

    // Register window lifecycle listener
    windowManager.addListener(AppWindowListener(minimizeToTray: true));
  }

  static Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false); // restore to taskbar
  }

  static Future<void> quit() async {
    await windowManager.destroy(); // actually exits the process
  }
}