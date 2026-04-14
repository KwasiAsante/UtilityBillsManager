import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:utility_bills_manager/utils/app_logger.dart';

import '../../data/models/sse_event.dart';
import '../api/api_service.dart';
import '_sse_web_stub.dart'
    if (dart.library.js_interop) '_sse_web.dart';

/// Manages a persistent Server-Sent Events connection to `/connect`.
///
/// Lifecycle:
///   1. Call [connect] once with the server URL and device ID.
///   2. Subscribe to [events] — it is a broadcast stream, so multiple
///      screens can listen simultaneously.
///   3. Call [disconnect] when the app no longer needs the connection.
///      Call [connect] again to re-establish it.
///
/// Reconnection:
///   Any unexpected close or error triggers an exponential back-off starting
///   at 5 s and capped at 60 s.  A `retry:` field from the server overrides
///   the base delay.  An explicit [disconnect] stops all reconnect attempts.
class SseService {
  static SseService? _instance;
  static SseService get instance => _instance ??= SseService._();
  SseService._();

  // ---------------------------------------------------------------------------
  // Public surface
  // ---------------------------------------------------------------------------

  /// Broadcast stream of domain events sent by the server.
  Stream<SseEvent> get events => _eventController.stream;

  /// Whether the SSE connection is currently active.
  bool get isConnected => _state == _SseState.connected;

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  final _eventController = StreamController<SseEvent>.broadcast();

  _SseState _state = _SseState.idle;
  http.Client? _client;
  StreamSubscription<String>? _lineSubscription;
  Timer? _reconnectTimer;

  // Reconnect config — base may be overridden by server's `retry:` field.
  int _baseDelayMs = 5000;
  int _attempt = 0;
  static const int _maxDelayMs = 60000;

  // Stored after first [connect] call so [_reconnect] never needs parameters.
  String? _serverUrl;
  String? _deviceId;

  // Per-event accumulator (reset after each dispatch or on reconnect).
  String _eventType = '';
  String _data = '';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Opens an SSE connection to [serverUrl]/connect, identifying this device
  /// with [deviceId] via the `x-device-id` request header.
  ///
  /// Ignored when already connecting or connected.
  Future<void> connect(String serverUrl, String deviceId) async {
    if (_state != _SseState.idle) return;

    _serverUrl = serverUrl;
    _deviceId = deviceId;
    _state = _SseState.connecting;

    if (kIsWeb) {
      _openWeb();
    } else {
      await _open();
    }
  }

  /// Closes the connection and cancels any pending reconnect timer.
  ///
  /// Call [connect] to re-establish.
  void disconnect() {
    AppLogger().d('[SSE] Disconnecting');
    _state = _SseState.disconnected;
    _reconnectTimer?.cancel();
    if (kIsWeb) {
      closeWebSse();
    } else {
      _cleanup(closeClient: true);
    }
    _attempt = 0;
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  void _openWeb() {
    assert(_serverUrl != null && _deviceId != null);
    final url = '$_serverUrl/connect';
    AppLogger().d('[SSE] Opening SSE connection (web): $url');

    openWebSse(
      url: url,
      deviceId: _deviceId!,
      onEvent: _eventController.add,
      onConnected: () {
        _state = _SseState.connected;
        _attempt = 0;
        AppLogger().d('[SSE] Stream opened (web)');
      },
      onClosed: () {
        if (_state == _SseState.disconnected) return;
        _state = _SseState.idle;
        _scheduleReconnect();
      },
    );
  }

  Future<void> _open() async {
    assert(_serverUrl != null && _deviceId != null);

    try {
      _client?.close();
      _client = LoggingHttpClient();

      // SseHandler identifies connections by `sseClientId` query param.
      final connectUrl = Uri.parse(
        '$_serverUrl/connect?sseClientId=${Uri.encodeComponent(_deviceId!)}',
      );
      final request = http.Request('GET', connectUrl);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request);

      if (response.statusCode != 200) {
        AppLogger().w('[SSE] Server returned ${response.statusCode}');
        _state = _SseState.idle;
        _scheduleReconnect();
        return;
      }

      _state = _SseState.connected;
      _attempt = 0;
      _resetAccumulator();
      AppLogger().d('[SSE] Stream opened');

      // Send deviceId as first message so the server can register this client.
      // SseHandler routes POSTs to the connection identified by sseClientId.
      unawaited(
        http.post(connectUrl, body: _deviceId).catchError(
          (Object e) {
            AppLogger().w('[SSE] Failed to register deviceId: $e');
            return http.Response('', 500);
          }
        ),
      );

      _lineSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onDone: _onDone,
            onError: _onError,
            cancelOnError: false,
          );
    } catch (e, stackTrace) {
      AppLogger().e('[SSE] Connection failed: $e', error: e, stackTrace: stackTrace);
      _state = _SseState.idle;
      _scheduleReconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // SSE line parser  (per spec §9.2)
  // ---------------------------------------------------------------------------

  void _onLine(String line) {
    // Comment / keep-alive heartbeat — ignore.
    if (line.startsWith(':')) return;

    // Empty line: dispatch the accumulated event (if any).
    if (line.isEmpty) {
      if (_eventType.isNotEmpty || _data.isNotEmpty) {
        _dispatch(_eventType, _data);
        _resetAccumulator();
      }
      return;
    }

    final colonIdx = line.indexOf(':');
    final String field;
    final String value;

    if (colonIdx == -1) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colonIdx);
      // Strip exactly one leading U+0020 space from the value if present.
      final raw = line.substring(colonIdx + 1);
      value = raw.startsWith(' ') ? raw.substring(1) : raw;
    }

    switch (field) {
      case 'event':
        _eventType = value;
      case 'data':
        // Multiple data lines are concatenated with U+000A per spec.
        _data = _data.isEmpty ? value : '$_data\n$value';
      case 'retry':
        final ms = int.tryParse(value);
        if (ms != null) {
          _baseDelayMs = ms;
          AppLogger().d('[SSE] Server set retry delay to ${ms}ms');
        }
      case 'id':
        // Last-event-id — could be used for resumption; stored if needed later.
        break;
    }
  }

  void _dispatch(String type, String rawData) {
    if (rawData.isEmpty) return;

    try {
      final json = jsonDecode(rawData) as Map<String, dynamic>;

      // Server embeds `type` in the JSON payload for unnamed data events.
      final typeName = type.isNotEmpty ? type : json['type'] as String? ?? '';

      if (typeName == 'connected') {
        AppLogger().i('[SSE] Server confirmed connection');
        return;
      }

      final eventType = switch (typeName) {
        'newBill' => SseEventType.newBill,
        'newPayment' => SseEventType.newPayment,
        _ => null,
      };

      if (eventType == null) {
        AppLogger().w('[SSE] Unknown event type "$typeName" — ignored');
        return;
      }

      final event = SseEvent(
        type: eventType,
        message: json['message'] as String? ?? '',
        data: json['data'] as Map<String, dynamic>? ?? {},
      );
      AppLogger().d('[SSE] ${event.type.name} — ${event.message}');
      _eventController.add(event);
    } catch (e) {
      AppLogger().e('[SSE] Failed to decode "$type" event: $e\nRaw: $rawData');
    }
  }

  void _resetAccumulator() {
    _eventType = '';
    _data = '';
  }

  // ---------------------------------------------------------------------------
  // Stream lifecycle
  // ---------------------------------------------------------------------------

  void _onDone() {
    AppLogger().d('[SSE] Stream closed by server');
    _state = _SseState.idle;
    _cleanup(closeClient: false); // stream is already done, client is spent
    _scheduleReconnect();
  }

  void _onError(Object error) {
    AppLogger().e('[SSE] Stream error: $error');
    _state = _SseState.idle;
    _cleanup(closeClient: true);
    _scheduleReconnect();
  }

  // ---------------------------------------------------------------------------
  // Reconnect — exponential back-off from _baseDelayMs, capped at _maxDelayMs
  // ---------------------------------------------------------------------------

  void _scheduleReconnect() {
    if (_state == _SseState.disconnected) return;

    final delay = min(_baseDelayMs * pow(2, _attempt).toInt(), _maxDelayMs);
    _attempt++;

    AppLogger().d('[SSE] Reconnect in ${delay}ms (attempt $_attempt)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (_state != _SseState.idle) return;
      if (kIsWeb) {
        _openWeb();
      } else {
        _open();
      }
    });
  }

  // ---------------------------------------------------------------------------

  void _cleanup({required bool closeClient}) {
    _lineSubscription?.cancel();
    _lineSubscription = null;
    if (closeClient) {
      _client?.close();
      _client = null;
    }
    _resetAccumulator();
  }
}

enum _SseState { idle, connecting, connected, disconnected }
