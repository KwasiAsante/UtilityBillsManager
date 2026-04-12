import 'dart:convert';

/// The type of server-sent event pushed to connected clients.
enum SseEventType { newBill, newPayment }

/// A server-sent event (SSE) payload pushed to connected clients over the
/// `/connect` stream.
///
/// Each event carries a [type] discriminator, a human-readable [message], and
/// the full [data] map of the entity (bill or payment) that triggered the
/// notification.
class SseEvent {
  final SseEventType type;
  final String message;
  final Map<String, dynamic> data;

  SseEvent({
    required this.type,
    required this.message,
    required this.data,
  });

  /// Formats this event as a valid SSE protocol string.
  ///
  /// Output format:
  /// ```
  /// event: <type>\ndata: <json>\n\n
  /// ```
  /// The double newline at the end signals the end of the event to the client.
  String toSseString() {
    final payload = jsonEncode({'message': message, 'data': data});
    return 'event: ${type.name}\ndata: $payload\n\n';
  }
}
