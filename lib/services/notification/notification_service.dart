import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/sse_event.dart';

/// Callback fired when the user taps a notification while the app is running.
typedef NotificationTapCallback = void Function(String? payload);

/// Abstract interface that every platform notification service must implement.
///
/// Each platform provides its own concrete implementation. The rest of the app
/// depends only on this interface — no platform checks, no switch statements.
abstract interface class NotificationService {
    StreamSubscription<SseEvent>? sseEventsSubscription;
    bool initialized = false;

    //region Lifecycle
    Future<void> initialize();

    void dispose();

    /// Registers the [GlobalKey<NavigatorState>] used by the notification tap
    /// handler to navigate to [MessagePreviewScreen].
    /// No-op on platforms that do not support tap navigation (web).
    void setNavigatorKey(GlobalKey<NavigatorState> key);

    /// Checks whether the app was cold-started via a compose notification tap
    /// and navigates to [MessagePreviewScreen] if so.
    /// No-op on platforms without local-notification tap support (web).
    Future<void> handleLaunchNotification();
    //endregion

    //region Local Notifications
    @protected Future<void> initLocalNotifications();

    Future<void> showNotification({
        required String title,
        required String body,
    });

    Future<void> cancelNotification(int id);

    Future<void> cancelAllNotifications();

    Future<void> cancelAllPendingNotifications();
    //endregion

    //region SSE
    @protected Future<void> connectSse(String apiBaseUrl, String deviceId);

    @protected void handleSseEvent(SseEvent event);
    //endregion

    //region Store and Repository Helpers
    @protected void addToStore({
        required SseEventType type,
        required String title,
        required String body,
    });

    @protected void reloadRepository(SseEventType type);
    //endregion
}

// // This file is the single public entry point for the notification service.
// // Dart's conditional import selects the correct implementation at compile time:
// //   • dart.library.js_interop      →  web     (Flutter Web)
// //   • BUILD_TARGET == 'windows'    →  windows (Windows desktop)
// //   • otherwise                    →  native  (Android / iOS / macOS / Linux)
// //
// // When building or running for Windows, pass --dart-define=BUILD_TARGET=windows:
// //   flutter run -d windows --dart-define=BUILD_TARGET=windows
// //   flutter build windows --dart-define=BUILD_TARGET=windows
// //
// // Consumers only ever import THIS file:
// //
// //   import 'notification_service.dart';
// //   NotificationService().initialize();
//
// export 'notification_service_native.dart'
//     if (dart.library.js_interop) 'notification_service_web.dart'
//     if (BUILD_TARGET == 'windows') 'notification_service_windows.dart';
