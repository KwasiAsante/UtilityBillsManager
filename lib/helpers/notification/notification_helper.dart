import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notificationPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> showNotification(String title, String body) async {
    const anddroidPlatformChannelSpecifics = AndroidNotificationDetails('bills_channel', 'Bill Notifications', importance: Importance.high, priority: Priority.high);
    const platformChannelSpecifics = NotificationDetails(android: anddroidPlatformChannelSpecifics);
    await _notificationPlugin.show(id: 0, title: title, body: body, notificationDetails: platformChannelSpecifics);
  }
}