import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/models/sse_event.dart';
import '../../utils/app_logger.dart';

/// Shared state and reconnect logic used by both platform implementations.
abstract class SseServiceBase {
  // ---------------------------------------------------------------------------
  // Public surface
  // ---------------------------------------------------------------------------

  /// Broadcast stream of domain events sent by the server.
  Stream<SseEvent> get events => eventController.stream;

  /// Whether the SSE connection is currently active.
  bool get isConnected => state == SseState.connected;

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  @protected final eventController = StreamController<SseEvent>.broadcast();

  @protected SseState state = SseState.idle;

  /// Reconnect config — base delay may be overridden by server's `retry:` field.
  @protected int baseDelayMs = 5000;
  @protected int attempt = 0;
  static const int maxDelayMs = 60000;

  @protected Timer? reconnectTimer;

  /// Stored after first [connect] so [scheduleReconnect] never needs parameters.
  @protected String? serverUrl;
  @protected String? deviceId;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Opens an SSE connection to [serverUrl]/connect, identifying this device
  /// with [deviceId].
  ///
  /// Ignored when already connecting or connected.
  Future<void> connect(String serverUrl, String deviceId) async {
    if (state != SseState.idle) return;

    this.serverUrl = serverUrl;
    this.deviceId = deviceId;
    state = SseState.connecting;

    await open();
  }

  /// Closes the connection and cancels any pending reconnect timer.
  ///
  /// Call [connect] to re-establish.
  void disconnect() {
    AppLogger().d('[SSE] Disconnecting');
    state = SseState.disconnected;
    reconnectTimer?.cancel();
    attempt = 0;
    close();
  }

  // ---------------------------------------------------------------------------
  // Platform-specific hooks
  // ---------------------------------------------------------------------------

  /// Opens the underlying transport connection.
  Future<void> open();

  /// Closes the underlying transport connection cleanly.
  void close();

  // ---------------------------------------------------------------------------
  // Reconnect — exponential back-off from [baseDelayMs], capped at [maxDelayMs]
  // ---------------------------------------------------------------------------

  void scheduleReconnect() {
    if (state == SseState.disconnected) return;

    final delay = min(baseDelayMs * pow(2, attempt).toInt(), maxDelayMs);
    attempt++;

    AppLogger().d('[SSE] Reconnect in ${delay}ms (attempt $attempt)');
    reconnectTimer?.cancel();
    reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (state != SseState.idle) return;
      state = SseState.connecting;
      open();
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers shared by native line-parser and web JSON decoder
  // ---------------------------------------------------------------------------

  /// Parses a raw type string into a known [SseEventType], or returns null.
  SseEventType? parseEventType(String? type) => switch (type) {
    'newBill' => SseEventType.newBill,
    'newPayment' => SseEventType.newPayment,
    _ => null,
  };

  void onConnected() {
    state = SseState.connected;
    attempt = 0;
    AppLogger().d('[SSE] Connected');
  }

  /// Forces a reconnect regardless of current state.
  ///
  /// Use when the app resumes from background/sleep and the SSE may be in a
  /// stuck [SseState.connecting] state (e.g. zombie TCP connection from before
  /// a sleep/wake cycle where [channel.ready] never resolved).
  Future<void> forceReconnect(String serverUrl, String deviceId) async {
    AppLogger().d('[SSE] Force reconnecting');
    reconnectTimer?.cancel();
    reconnectTimer = null;
    close();
    state = SseState.idle;
    attempt = 0;
    await connect(serverUrl, deviceId);
  }

  void onClosed() {
    AppLogger().d('[SSE] Connection closed by server');
    if (state == SseState.disconnected) return;
    state = SseState.idle;
    scheduleReconnect();
  }
}

enum SseState { idle, connecting, connected, disconnected }
