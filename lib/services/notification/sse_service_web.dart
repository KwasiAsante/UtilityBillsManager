import 'dart:async';
import 'dart:convert';

import 'package:sse/client/sse_client.dart';

import 'sse_service_base.dart';
import '../../data/models/sse_event.dart';
import '../../utils/app_logger.dart';

/// Concrete [SseServiceBase] for Flutter Web.
///
/// Uses the `sse` package's [SseClient], which wraps the browser's native
/// `EventSource` API.
class SseService extends SseServiceBase {
  static SseService? _instance;
  static SseService get instance => _instance ??= SseService._();
  SseService._();

  SseClient? _activeClient;

  // ---------------------------------------------------------------------------
  // open / close
  // ---------------------------------------------------------------------------

  @override
  Future<void> open() async {
    assert(serverUrl != null && deviceId != null);
    final url = '$serverUrl/connect';
    AppLogger().d('[SSE] Opening SSE connection: $url');

    close();

    final client = SseClient(url, debugKey: deviceId);
    _activeClient = client;

    client.onConnected.then((_) {
      AppLogger().d('[SSE] Connected — sending deviceId');
      // Identify this device to the server as the first message.
      client.sink.add(deviceId!);
      onConnected();
    }).catchError((Object e) {
      AppLogger().e('[SSE] Connection failed: $e');
      close();
      onClosed();
    });

    client.stream.listen(
      _onMessage,
      onError: (Object e) {
        AppLogger().e('[SSE] Stream error: $e');
        close();
        onClosed();
      },
      onDone: () {
        AppLogger().d('[SSE] Stream closed');
        onClosed();
      },
    );
  }

  @override
  void close() {
    _activeClient?.close();
    _activeClient = null;
  }

  // ---------------------------------------------------------------------------
  // Message decoding
  // ---------------------------------------------------------------------------

  void _onMessage(String message) {
    try {
      final map = jsonDecode(message) as Map<String, dynamic>;
      final eventType = parseEventType(map['type'] as String?);
      if (eventType == null) return;

      final event = SseEvent(
        type: eventType,
        message: map['message'] as String? ?? '',
        data: (map['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      AppLogger().d('[SSE] ${event.type.name} — ${event.message}');
      eventController.add(event);
    } catch (e) {
      AppLogger().e('[SSE] Failed to decode message: $e\nRaw: $message');
    }
  }
}
