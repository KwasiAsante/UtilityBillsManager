import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sse_channel/sse_channel.dart';
import 'package:utility_bills_manager/utils/app_logger.dart';

import 'sse_service_base.dart';
import '../../data/models/sse_event.dart';

/// Concrete [SseServiceBase] for Android, iOS, macOS, Windows, Linux.
///
/// Uses [SseChannel] (the `sse_channel` package) which handles the
/// HTTP GET + bidirectional POST sink over dart:io.
class SseService extends SseServiceBase {
  static SseService? _instance;
  static SseService get instance => _instance ??= SseService._();
  SseService._();

  SseChannel? _activeChannel;

  /// Test-only seam for injecting a channel directly, bypassing the real
  /// network connection [open] establishes.
  @visibleForTesting
  set debugActiveChannel(SseChannel? channel) => _activeChannel = channel;

  // ---------------------------------------------------------------------------
  // open / close
  // ---------------------------------------------------------------------------

  @override
  Future<void> open() async {
    assert(serverUrl != null && deviceId != null);
    final url = '$serverUrl/connect';
    AppLogger().d('[SSE] Opening SSE connection: $url');

    close();

    try {
      final channel = SseChannel.connect(Uri.parse(url), debugKey: deviceId);
      _activeChannel = channel;

      channel.ready
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              AppLogger().w('[SSE] Connection handshake timed out after 15s');
              close();
              onClosed();
            },
          )
          .then((_) {
            AppLogger().d('[SSE] Connected — sending deviceId');
            // Identify this device to the server as the first message.
            channel.sink.add(deviceId!);
            onConnected();
          })
          .catchError((Object e, StackTrace stackTrace) {
            AppLogger().e(
              '[SSE] Connection failed: $e',
              error: e,
              stackTrace: stackTrace,
            );
            close();
            onClosed();
          });

      channel.stream.listen(
        _onMessage,
        onError: (Object error, StackTrace stackTrace) {
          if (error is SseChannelException) {
            AppLogger().e(
              '[SSE] Stream error: $error',
              error: error,
              stackTrace: stackTrace,
            );
          }
          close();
          onClosed();
        },
        onDone: () {
          AppLogger().d('[SSE] Stream closed');
          onClosed();
        },
      );
    } catch (e, stackTrace) {
      AppLogger().e(
        '[SSE] Connection failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
      close();
      onClosed();
    }
  }

  @override
  void close() {
    try {
      _activeChannel?.sink.close();
    } catch (e) {
      // The transport may have already torn itself down independently of
      // this call — e.g. the OS dropped the connection while the app was
      // backgrounded (opening the share sheet triggers exactly this). The
      // sink is then already closed, so SseSinkImpl.close()'s add('close')
      // throws "Bad state: Cannot add event after closing". There's nothing
      // further to close in that case.
      AppLogger().d('[SSE] Sink already closed: $e');
    }
    _activeChannel?.close();
    _activeChannel = null;
  }

  // ---------------------------------------------------------------------------
  // Message decoding
  // ---------------------------------------------------------------------------

  void _onMessage(dynamic raw) {
    try {
      // SseChannel surfaces MessageEvent-like objects; extract `.data`.
      final data = (raw as dynamic).data as String?;
      if (data == null || data.isEmpty) return;

      Map<String, dynamic>? map;
      try {
        map = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        // Server occasionally double-encodes — unwrap once more.
        map = jsonDecode(jsonDecode(data) as String) as Map<String, dynamic>;
      }

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
      AppLogger().e('[SSE] Failed to decode message: $e\nRaw: $raw');
    }
  }
}
