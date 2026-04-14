import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> requestWebNotificationPermission() async {
  if (web.Notification.permission == 'default') {
    await web.Notification.requestPermission().toDart;
  }
}

void showWebNotification({required String title, required String body}) {
  if (web.Notification.permission != 'granted') return;
  web.Notification(
    title,
    web.NotificationOptions(body: body),
  );
}
