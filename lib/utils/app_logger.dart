import 'package:logger/logger.dart';

/// Singleton logger backed by the [logger](https://pub.dev/packages/logger) package.
///
/// Use the level helpers matching the severity of each message:
/// - [d] – debug / verbose flow information
/// - [i] – informational milestones (e.g. server started)
/// - [w] – warnings / unexpected-but-recoverable situations
/// - [e] – errors that need investigation
///
/// The underlying [Logger] uses the default [DevelopmentFilter], so output is
/// suppressed automatically in release builds.
///
/// Each log message is automatically prefixed with the calling class and method
/// name, e.g. `[ApiService.fetchBills] Error fetching bills`.
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();

  factory AppLogger() => _instance;

  AppLogger._internal();

  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

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
      final webMatch =
          RegExp(r'package:[^\s]+/([^/]+)\.dart\s+\d+:\d+\s+(.+)$')
              .firstMatch(frame);
      if (webMatch != null) {
        return '[${webMatch.group(1)!}.${webMatch.group(2)!}] ';
      }
    }
    return '';
  }

  void t(dynamic message, {Object? error, StackTrace? stackTrace}) {
    final caller = _caller(StackTrace.current);
    _logger.t('$caller$message', error: error, stackTrace: stackTrace);
  }

  void d(dynamic message, {Object? error, StackTrace? stackTrace}) {
    final caller = _caller(StackTrace.current);
    _logger.d('$caller$message', error: error, stackTrace: stackTrace);
  }

  void i(dynamic message, {Object? error, StackTrace? stackTrace}) {
    final caller = _caller(StackTrace.current);
    _logger.i('$caller$message', error: error, stackTrace: stackTrace);
  }

  void w(dynamic message, {Object? error, StackTrace? stackTrace}) {
    final caller = _caller(StackTrace.current);
    _logger.w('$caller$message', error: error, stackTrace: stackTrace);
  }

  void e(dynamic message, {Object? error, StackTrace? stackTrace}) {
    final caller = _caller(StackTrace.current);
    _logger.e('$caller$message', error: error, stackTrace: stackTrace);
  }

  void f(dynamic message, {Object? error, StackTrace? stackTrace}) {
    final caller = _caller(StackTrace.current);
    _logger.f('$caller$message', error: error, stackTrace: stackTrace);
  }
}
