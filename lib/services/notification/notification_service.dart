// This file is the single public entry point for the notification service.
// Dart's conditional import selects the correct implementation at compile time:
//   • dart.library.js_interop      →  web     (Flutter Web)
//   • BUILD_TARGET == 'windows'    →  windows (Windows desktop)
//   • otherwise                    →  native  (Android / iOS / macOS / Linux)
//
// When building or running for Windows, pass --dart-define=BUILD_TARGET=windows:
//   flutter run -d windows --dart-define=BUILD_TARGET=windows
//   flutter build windows --dart-define=BUILD_TARGET=windows
//
// Consumers only ever import THIS file:
//
//   import 'notification_service.dart';
//   NotificationService().initialize();

export 'notification_service_native.dart'
    if (dart.library.js_interop) 'notification_service_web.dart'
    if (BUILD_TARGET == 'windows') 'notification_service_windows.dart';
