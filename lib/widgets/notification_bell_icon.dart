import 'package:flutter/material.dart';

import '../services/notification/app_notification_store.dart';
import 'notification_panel.dart';

/// An [AppBar] action that shows a bell icon with an unread-count badge.
///
/// Tapping the icon opens [NotificationPanel] and marks all notifications read.
/// Drop it directly into any screen's `AppBar.actions`:
///
/// ```dart
/// appBar: AppBar(
///   actions: [
///     const NotificationBellIcon(),
///     ...
///   ],
/// )
/// ```
class NotificationBellIcon extends StatelessWidget {
  const NotificationBellIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppNotificationStore(),
      builder: (context, _) {
        final unread = AppNotificationStore().unreadCount;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              tooltip: 'Notifications',
              icon: Icon(
                unread > 0
                    ? Icons.notifications
                    : Icons.notifications_none_outlined,
              ),
              onPressed: () => NotificationPanel.show(context),
            ),
            if (unread > 0)
              Positioned(
                top: 8,
                right: 8,
                child: _Badge(count: unread),
              ),
          ],
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(8),
      ),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onError,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
