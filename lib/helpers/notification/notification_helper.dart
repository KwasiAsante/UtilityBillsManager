// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
//
// /// Static wrapper around [FlutterLocalNotificationsPlugin] for displaying
// /// local push notifications.
// ///
// /// Currently targets Android only (via the `bills_channel` notification
// /// channel). iOS / macOS / Windows support can be added by extending
// /// [showNotification] with the corresponding platform-specific details.
// class NotificationHelper {
//   static final FlutterLocalNotificationsPlugin _notificationPlugin = FlutterLocalNotificationsPlugin();
//
//   /// Displays a high-priority local notification with the given [title] and
//   /// [body] text on the `bills_channel` Android notification channel.
//   static Future<void> showNotification(String title, String body) async {
//     const anddroidPlatformChannelSpecifics = AndroidNotificationDetails('bills_channel', 'Bill Notifications', importance: Importance.high, priority: Priority.high);
//     const platformChannelSpecifics = NotificationDetails(android: anddroidPlatformChannelSpecifics);
//     await _notificationPlugin.show(id: 0, title: title, body: body, notificationDetails: platformChannelSpecifics);
//   }
// }