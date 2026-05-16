import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'server_log_output.dart';
import '../../config/app_config.dart';
import '../../services/api/api_service.dart';

/// Fires at midnight each day and uploads any log lines from [logOutput.byteOffset]
/// to EOF in today's log file, filling gaps left by failed real-time pushes.
///
/// After a successful upload, resets [logOutput.byteOffset] to 0 so the new
/// day starts fresh.
class LogUploadService {
  LogUploadService({
    required ServerLogOutput logOutput,
    Future<String> Function()? getDeviceId,
    Future<String> Function()? getLogsDir,
  })  : _logOutput = logOutput,
        _getDeviceId = getDeviceId ?? (() => AppConfig.deviceId),
        _getLogsDir = getLogsDir ?? _defaultLogsDir;

  final ServerLogOutput _logOutput;
  final Future<String> Function() _getDeviceId;
  final Future<String> Function() _getLogsDir;

  Timer? _timer;
  bool _stopped = false;

  /// Starts the midnight upload cycle.
  ///
  /// Call once during app startup (after [AppConfig.init]).
  void start() {
    _stopped = false;
    _scheduleNextMidnight();
  }

  /// Cancels the scheduled timer. Call on app shutdown if needed.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Reads today's log file from [logOutput.byteOffset] to EOF and POSTs
  /// the chunk to `POST /logs/device/upload`.
  ///
  /// On HTTP 200, resets [logOutput.byteOffset] to 0 for the new day.
  /// Failures are silent — no retry in v1.
  Future<void> uploadGap() async {
    final logsDir = await _getLogsDir();
    final today = _todayStr();
    final file = File('$logsDir/$today.log');

    if (!await file.exists()) return;

    final fileLength = await file.length();
    final offset = _logOutput.byteOffset;
    if (fileLength <= offset) return;

    final raf = await file.open();
    try {
      await raf.setPosition(offset);
      final bytes = await raf.read(fileLength - offset);
      final chunk = utf8.decode(bytes, allowMalformed: true);

      final deviceId = await _getDeviceId();

      final result = await ApiService.log().uploadDeviceLog(deviceId, chunk);

      if (result.isSuccess) {
        _logOutput.resetByteOffset();
      }
    } catch (_) {
      // Silent — EOD upload failures are not retried in v1.
    } finally {
      await raf.close();
    }
  }

  void _scheduleNextMidnight() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final until = tomorrow.difference(now);
    _timer = Timer(until, _onMidnight);
  }

  Future<void> _onMidnight() async {
    await uploadGap();
    // Always reset — at midnight we switch to a new log file (new date), so the
    // offset must start at 0 regardless of whether the upload succeeded.
    // Failed uploads result in that gap being lost (acceptable in v1, no retry).
    _logOutput.resetByteOffset();
    if (!_stopped) _scheduleNextMidnight();
  }

  static String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  static Future<String> _defaultLogsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/logs';
  }
}
