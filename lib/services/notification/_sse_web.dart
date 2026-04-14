import 'dart:convert';

import 'package:sse/client/sse_client.dart';

import '../../data/models/sse_event.dart';
import '../../utils/app_logger.dart';

SseClient? _activeClient;

void openWebSse({
  required String url,
  required String deviceId,
  required void Function(SseEvent) onEvent,
  required void Function() onConnected,
  required void Function() onClosed,
}) {
  closeWebSse();

  AppLogger().d('[SSE] Creating SseClient for $url');
  final client = SseClient(url, debugKey: deviceId);
  _activeClient = client;

  client.onConnected.then((_) {
    AppLogger().d('[SSE] Connected — sending deviceId (web)');
    // Identify this device to the server as the first message.
    client.sink.add(deviceId);
    onConnected();
  }).catchError((Object e) {
    AppLogger().e('[SSE] Connection failed: $e');
    closeWebSse();
    onClosed();
  });

  client.stream.listen(
    (message) {
      try {
        final map = jsonDecode(message) as Map<String, dynamic>;
        final type = map['type'] as String?;
        final eventType = switch (type) {
          'newBill' => SseEventType.newBill,
          'newPayment' => SseEventType.newPayment,
          _ => null,
        };
        if (eventType == null) return;
        final event = SseEvent(
          type: eventType,
          message: map['message'] as String? ?? '',
          data: (map['data'] as Map?)?.cast<String, dynamic>() ?? {},
        );
        AppLogger().d('[SSE] ${event.type.name} — ${event.message} (web)');
        onEvent(event);
      } catch (e) {
        AppLogger().e('[SSE] Failed to decode message: $e\nRaw: $message');
      }
    },
    onError: (Object e) {
      AppLogger().e('[SSE] Stream error: $e');
      closeWebSse();
      onClosed();
    },
    onDone: () {
      AppLogger().d('[SSE] Stream closed (web)');
      onClosed();
    },
  );
}

void closeWebSse() {
  _activeClient?.close();
  _activeClient = null;
}
