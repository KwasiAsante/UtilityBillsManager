import 'sse_event.dart';

/// An in-memory notification created when the server pushes a [SseEvent].
class AppNotification {
  final String id;
  final SseEventType type;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });
}
