import 'package:flutter/foundation.dart';

import '../../data/models/app_notification.dart';

/// In-memory store for [AppNotification]s received from the server.
///
/// Holds at most [maxNotifications] entries. When full, the oldest
/// notification (index 0) is silently dropped to make room for the new one.
///
/// Screens observe this store via [addListener] / [ListenableBuilder] and
/// rebuild whenever the list or read-state changes.
class AppNotificationStore extends ChangeNotifier {
  static final AppNotificationStore _instance =
      AppNotificationStore._internal();
  factory AppNotificationStore() => _instance;
  AppNotificationStore._internal();

  static const int maxNotifications = 10;

  final List<AppNotification> _notifications = [];

  /// A read-only view of the stored notifications, newest last.
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  /// Number of notifications the user has not yet read.
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Adds [notification], evicting the oldest entry if the store is full.
  void add(AppNotification notification) {
    if (_notifications.length >= maxNotifications) {
      _notifications.removeAt(0);
    }
    _notifications.add(notification);
    notifyListeners();
  }

  /// Marks every stored notification as read.
  void markAllRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  /// Removes the notification with the given [id].
  void dismiss(String id) {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }
}
