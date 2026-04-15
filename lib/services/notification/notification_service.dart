// This file is the single public entry point for the notification service.
// Dart's conditional import selects the correct implementation at compile time:
//   • dart.library.js_interop      →  web     (Flutter Web)
//   • dart.library.io + Windows    →  windows (Windows desktop)
//   • otherwise                    →  native  (Android / iOS / macOS / Linux)
//
// Consumers only ever import THIS file:
//
//   import 'notification_service.dart';
//   NotificationService().initialize();

export 'notification_service_native.dart'
    if (dart.library.js_interop) 'notification_service_web.dart'
    if (dart.library.io) 'notification_service_windows.dart';
