import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/logs/server_log_output.dart';

// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------

/// Always allows evert log event through, regardless of build mode or level.
class _AllowAllFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

// ---------------------------------------------------------------------------
// File output – daily rotation with per-file size cap
// ---------------------------------------------------------------------------

/// Writes log events to plain-text files under `<documents>/logs/`.
///
/// Naming convention:
///   • First file of the day → `yyyy-MM-dd.log`
///   • Subsequent files (after size cap is reached) → `yyyy-MM-dd_1.log`,
///     `yyyy-MM-dd_2.log`, …
///
/// Initialization is async (requires [path_provider]); messages emitted
/// before the directory is ready are queued and flushed once ready.
class _FileLogOutput extends LogOutput {
  /// Maximum bytes written to a single log file before rolling over.
  final int maxFileSizeBytes;

  _FileLogOutput({this.maxFileSizeBytes = 5 * 1024 * 1024}) {
    if (!kIsWeb) _initAsync();
  }

  Directory? _logsDir;
  File? _currentFile;
  String? _currentDateStr;
  bool _ready = false;
  final List<String> _queue = [];

  Future<void> _initAsync() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _logsDir =
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
              ? Directory('${appDir.path}/Utility Bills Manager/logs')
              : Directory('${appDir.path}/logs');
      await _logsDir!.create(recursive: true);
    } catch (_) {
      // If we cannot create the directory, disable file logging silently.
    } finally {
      _ready = true;
      _flush();
    }
  }

  void _flush() {
    for (final entry in _queue) {
      _write(entry);
    }
    _queue.clear();
  }

  @override
  void output(OutputEvent event) {
    if (kIsWeb) return;

    final entry = _format(event);
    if (!_ready) {
      _queue.add(entry);
    } else {
      _write(entry);
    }
  }

  // --- formatting -----------------------------------------------------------

  String _format(OutputEvent event) {
    final ts = DateTime.now().toIso8601String();
    final lvl = event.level.name.toUpperCase().padRight(5);
    final body = event.lines.map(_stripAnsi).join('\n        ');
    return '[$ts] [$lvl] $body\n';
  }

  static final _ansiRe = RegExp(r'\x1B\[[0-9;]*[a-zA-Z]');
  String _stripAnsi(String s) => s.replaceAll(_ansiRe, '');

  // --- file resolution ------------------------------------------------------

  void _write(String entry) {
    if (_logsDir == null) return;
    try {
      _resolveFile().writeAsStringSync(entry, mode: FileMode.append);
    } catch (_) {
      // Silently ignore transient I/O errors.
    }
  }

  File _resolveFile() {
    final today = _today();

    if (_currentDateStr != today) {
      _currentDateStr = today;
      _currentFile = null;
    }

    if (_currentFile != null) {
      try {
        if (_currentFile!.lengthSync() >= maxFileSizeBytes) {
          _currentFile = null;
        }
      } catch (_) {
        _currentFile = null;
      }
    }

    _currentFile ??= _nextAvailableFile(today);
    return _currentFile!;
  }

  /// Returns `yyyy-MM-dd` for today.
  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Finds a file that either does not yet exist or has room left.
  File _nextAvailableFile(String date) {
    final base = '${_logsDir!.path}/$date';
    var candidate = File('$base.log');
    var idx = 1;
    while (candidate.existsSync() &&
        candidate.lengthSync() >= maxFileSizeBytes) {
      candidate = File('${base}_$idx.log');
      idx++;
    }
    return candidate;
  }
}

// ---------------------------------------------------------------------------
// AppLogger
// ---------------------------------------------------------------------------

/// Singleton logger with three independent output destinations:
///
/// 1. **Console (stdout)** – always active, coloured [PrettyPrinter] output.
/// 2. **File** – plain-text daily-rotating files under
///    `<documents>/logs/yyyy-MM-dd[_N].log`.  A new file is created once the
///    current one reaches [_fileMaxBytes] (default 5 MB).
/// 3. **Server** – forwarded to [ServerLogOutput] for remote upload.
///
/// Every log method accepts two optional routing flags in addition to the
/// standard `error` / `stackTrace` parameters:
///
/// - `toFile` (default `true`) — write this message to the log file.
/// - `toServer` (default `true`) — forward this message to the server.
///
/// Use the level helpers matching the severity of each message:
/// - [t] – trace / extremely verbose
/// - [d] – debug / verbose flow information
/// - [i] – informational milestones (e.g. server started)
/// - [w] – warnings / unexpected-but-recoverable situations
/// - [e] – errors that need investigation
/// - [f] – fatal / unrecoverable failures
///
/// Each message is automatically prefixed with the calling class/method name,
/// e.g. `[ApiService.fetchBills] Error fetching bills`.
class AppLogger {
  static const int _fileMaxBytes = 5 * 1024 * 1024; // 5 MB

  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;

  AppLogger._internal();

  /// The server log output — exposed so [LogUploadService] can receive the same
  /// instance that is registered in the logger.
  final ServerLogOutput serverLogOutput = ServerLogOutput();

  static PrettyPrinter get _printer => PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  );

  late final Logger _consoleLogger = Logger(
    filter: _AllowAllFilter(),
    printer: _printer,
    output: ConsoleOutput(),
  );

  late final Logger _fileLogger = Logger(
    filter: _AllowAllFilter(),
    printer: _printer,
    output: _FileLogOutput(maxFileSizeBytes: _fileMaxBytes),
  );

  late final Logger _serverLogger = Logger(
    filter: _AllowAllFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 1000, // avoid line breaks in server logs
      colors: false, // strip ANSI color codes for server logs
      printEmojis: false, // avoid emojis in server logs
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    output: serverLogOutput,
  );

  // --- caller resolution ----------------------------------------------------

  /// Returns a `[caller] ` prefix by finding the first non-logger, non-SDK frame.
  ///
  /// Handles both VM format (`#N  Class.method (package:...)`) and the web DDC
  /// format (`package:path/file.dart line:col  method`).
  static String _caller(StackTrace stackTrace) {
    for (final raw in stackTrace.toString().split('\n')) {
      final frame = raw.trim();
      if (frame.isEmpty) continue;
      if (frame.contains('dart-sdk/') || frame.contains('app_logger.dart')) {
        continue;
      }

      // VM / native format: #N      ClassName.methodName (package:...)
      final vmMatch = RegExp(r'#\d+\s+(.+?)\s+\(').firstMatch(frame);
      if (vmMatch != null) return '[${vmMatch.group(1)}] ';

      // Web DDC format: package:path/to/file.dart line:col   methodName
      final webMatch = RegExp(
        r'package:[^\s]+/([^/]+)\.dart\s+\d+:\d+\s+(.+)$',
      ).firstMatch(frame);
      if (webMatch != null) {
        return '[${webMatch.group(1)!}.${webMatch.group(2)!}] ';
      }
    }
    return '';
  }

  void _log(
    void Function(Logger) logFn, {
    required bool toFile,
    required bool toServer,
  }) {
    logFn(_consoleLogger);
    if (toFile) logFn(_fileLogger);
    if (toServer) logFn(_serverLogger);
  }

  // --- public API -----------------------------------------------------------

  void t(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    bool toFile = true,
    bool toServer = true,
  }) {
    final msg = '${_caller(StackTrace.current)}$message';
    _log(
      (l) => l.t(msg, error: error, stackTrace: stackTrace),
      toFile: toFile,
      toServer: toServer,
    );
  }

  void d(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    bool toFile = true,
    bool toServer = true,
  }) {
    final msg = '${_caller(StackTrace.current)}$message';
    _log(
      (l) => l.d(msg, error: error, stackTrace: stackTrace),
      toFile: toFile,
      toServer: toServer,
    );
  }

  void i(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    bool toFile = true,
    bool toServer = true,
  }) {
    final msg = '${_caller(StackTrace.current)}$message';
    _log(
      (l) => l.i(msg, error: error, stackTrace: stackTrace),
      toFile: toFile,
      toServer: toServer,
    );
  }

  void w(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    bool toFile = true,
    bool toServer = true,
  }) {
    final msg = '${_caller(StackTrace.current)}$message';
    _log(
      (l) => l.w(msg, error: error, stackTrace: stackTrace),
      toFile: toFile,
      toServer: toServer,
    );
  }

  void e(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    bool toFile = true,
    bool toServer = true,
  }) {
    final msg = '${_caller(StackTrace.current)}$message';
    _log(
      (l) => l.e(msg, error: error, stackTrace: stackTrace),
      toFile: toFile,
      toServer: toServer,
    );
  }

  void f(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    bool toFile = true,
    bool toServer = true,
  }) {
    final msg = '${_caller(StackTrace.current)}$message';
    _log(
      (l) => l.f(msg, error: error, stackTrace: stackTrace),
      toFile: toFile,
      toServer: toServer,
    );
  }
}
