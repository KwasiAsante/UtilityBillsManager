import 'dart:convert';

/// The type of server-sent event pushed to connected clients.
///
/// [billSummaryReminder] is sent once per month, when that month's electric,
/// gas, and internet bills have all arrived, as a prompt to send the rentors
/// a bill summary. Its `data` is `{'month': 'yyyy-MM'}`.
enum SseEventType { newBill, newPayment, billSummaryReminder }

/// Parses a server-sent event type string (the enum value's name, e.g.
/// `'newBill'`) into a known [SseEventType], or returns null for unknown
/// types.
///
/// Shared by the SSE decoders and the FCM handlers so every channel
/// recognises the same set of types.
SseEventType? parseSseEventType(String? type) =>
    type == null ? null : SseEventType.values.asNameMap()[type];

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
