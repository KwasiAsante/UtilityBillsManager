import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models/app_notification.dart';
import '../data/models/sse_event.dart';
import '../services/notification/app_notification_store.dart';

/// Modal bottom sheet that lists in-app notifications.
///
/// Show via [NotificationPanel.show]. Each entry can be dismissed
/// individually; the full list can be cleared at once.
class NotificationPanel extends StatelessWidget {
  const NotificationPanel({super.key});

  static void show(BuildContext context) {
    AppNotificationStore().markAllRead();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const NotificationPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: AppNotificationStore(),
          builder: (context, _) {
            final notifications = AppNotificationStore().notifications;
            return Column(
              children: [
                _Header(hasNotifications: notifications.isNotEmpty),
                Expanded(
                  child: notifications.isEmpty
                      ? const _EmptyState()
                      : _NotificationList(
                          notifications: notifications,
                          scrollController: scrollController,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hasNotifications});

  final bool hasNotifications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Text(
            'Notifications',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          if (hasNotifications)
            TextButton(
              onPressed: () {
                AppNotificationStore().notifications
                    .map((n) => n.id)
                    .toList()
                    .forEach(AppNotificationStore().dismiss);
              },
              child: const Text('Clear all'),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 48,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No notifications',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.notifications,
    required this.scrollController,
  });

  final List<AppNotification> notifications;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    // Show newest first.
    final reversed = notifications.reversed.toList();
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: reversed.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) =>
          _NotificationTile(notification: reversed[index]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => AppNotificationStore().dismiss(notification.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colorScheme.errorContainer,
        child: Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(
            notification.type == SseEventType.newBill
                ? Icons.receipt_outlined
                : Icons.payment_outlined,
            size: 20,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          notification.title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: notification.isRead
                    ? FontWeight.normal
                    : FontWeight.bold,
              ),
        ),
        subtitle: Text(
          notification.body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _formatTime(notification.timestamp),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
              ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) {
      return DateFormat.jm().format(dt);
    }
    return DateFormat('MMM d').format(dt);
  }
}
