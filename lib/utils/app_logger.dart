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

  void t(dynamic message, {Object? error, StackTrace? stackTrace}) =>
      _logger.t(message, error: error, stackTrace: stackTrace);

  void d(dynamic message, {Object? error, StackTrace? stackTrace}) =>
      _logger.d(message, error: error, stackTrace: stackTrace);

  void i(dynamic message, {Object? error, StackTrace? stackTrace}) =>
      _logger.i(message, error: error, stackTrace: stackTrace);

  void w(dynamic message, {Object? error, StackTrace? stackTrace}) =>
      _logger.w(message, error: error, stackTrace: stackTrace);

  void e(dynamic message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  void f(dynamic message, {Object? error, StackTrace? stackTrace}) =>
      _logger.f(message, error: error, stackTrace: stackTrace);
}
