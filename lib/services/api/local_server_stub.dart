import '../../utils/app_logger.dart';

/// Fallback `startServer` implementation for platforms that do not support
/// running a local HTTP server (e.g. Flutter web).
Future<void> startServer() async {
  // This is intentionally a no-op on unsupported platforms.
  AppLogger().d('startServer() is not supported on this platform. Skipping.');
}

