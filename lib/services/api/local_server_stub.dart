import 'package:flutter/foundation.dart';

/// Fallback `startServer` implementation for platforms that do not support
/// running a local HTTP server (e.g. Flutter web).
Future<void> startServer() async {
  if (kDebugMode) {
    // This is intentionally a no-op on unsupported platforms.
    print('startServer() is not supported on this platform. Skipping.');
  }
}

