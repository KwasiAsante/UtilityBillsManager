import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notificationPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> showNotification(String title, String body) async {
    const anddroidPlatformChannelSpecifics = AndroidNotificationDetails('bills_channel', 'Bill Notifications', importance: Importance.high, priority: Priority.high);
    const platformChannelSpecifics = NotificationDetails(android: anddroidPlatformChannelSpecifics);
    await _notificationPlugin.show(0, title, body, platformChannelSpecifics);
  }
}