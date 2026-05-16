import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../../config/app_config.dart';
import '../../services/api/api_service.dart';

/// Streams log events to the remote Loki endpoint via `POST /logs/device`.
///
/// - Buffers lines internally; flushes every [_flushInterval] or when
///   [_bufferMaxLines] lines accumulate.
/// - On successful flush, [byteOffset] advances by the UTF-8 byte count of
///   the sent lines — this mirrors the write position in the on-device log
///   file so [LogUploadService] can read the remainder at end-of-day.
/// - On any failure (network error, non-200) the lines are dropped silently;
///   the end-of-day upload covers the gap.
/// - [_format] is intentionally identical to `_FileLogOutput._format` so that
///   [byteOffset] byte counts align with the on-device log file bytes.
class ServerLogOutput extends LogOutput {
  ServerLogOutput({
    Future<String> Function()? getDeviceId,
  })  : _getDeviceId = getDeviceId ?? (() => AppConfig.deviceId);

  final Future<String> Function() _getDeviceId;

  final List<String> _buffer = [];
  int _byteOffset = 0;
  Timer? _timer;
  bool _flushing = false;
  Level _level = Level.all;

  static const _flushInterval = Duration(seconds: 3);
  static const _bufferMaxLines = 20;

  /// Bytes of today's log file successfully confirmed delivered to the server.
  int get byteOffset => _byteOffset;

  /// Resets the offset to 0 (called by [LogUploadService] at end-of-day after
  /// the gap-fill upload succeeds, so the new day starts from byte 0).
  void resetByteOffset() => _byteOffset = 0;

  /// Sets the offset to a specific value.
  ///
  /// Exposed for testing only — do not call in production code.
  @visibleForTesting
  void setByteOffset(int offset) => _byteOffset = offset;

  @override
  void output(OutputEvent event) {
    if (kIsWeb) return;
    final entry = _format(event);
    _buffer.add(entry);
    _level = event.level;
    _timer ??= Timer.periodic(_flushInterval, (_) => _flush());
    if (_buffer.length >= _bufferMaxLines) _flush();
  }

  Future<void> _flush() async {
    if (_flushing || _buffer.isEmpty) return;
    _flushing = true;

    final lines = List<String>.from(_buffer);
    _buffer.clear();

    try {
      final deviceId = await _getDeviceId();

      final result = await ApiService.log().deviceLog(deviceId, lines, _level);

      if (result.isSuccess) {
        final byteCount = lines.fold<int>(
          0,
          (sum, line) => sum + utf8.encode(line).length,
        );
        _byteOffset += byteCount;
      }
    } catch (_) {
      // Network unavailable — drop silently; EOD upload covers the gap.
    } finally {
      _flushing = false;
    }
  }

  static String _format(OutputEvent event) {
    final ts = DateTime.now().toIso8601String();
    final lvl = event.level.name.toUpperCase().padRight(5);
    final body = event.lines.map(_stripAnsi).join('\n        ');
    return '[$ts] [$lvl] $body\n';
  }

  static final _ansiRe = RegExp(r'\x1B\[[0-9;]*[a-zA-Z]');
  static String _stripAnsi(String s) => s.replaceAll(_ansiRe, '');

  @override
  Future<void> destroy() async {
    _timer?.cancel();
    _timer = null;
    await _flush(); // best-effort on shutdown
    await super.destroy();
  }
}
