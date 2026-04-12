/// Stub implementation of [initDb] — no-op fallback used when neither
/// [dart.library.html] nor [dart.library.io] is available.
///
/// In practice this is never called at runtime; it only satisfies the Dart
/// analyser when resolving conditional exports on unknown platforms.
void initDb() {}