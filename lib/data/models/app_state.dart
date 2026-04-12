/// App-wide singleton that stores lightweight runtime state shared between
/// screens and service layers.
///
/// Key flag: [localDB] — when `true`, all helpers read/write directly through
/// [DatabaseHelper]; when `false` they route requests through [ApiService]
/// (HTTP client mode).
class AppState {
  static final AppState _instance = AppState._internal();
  
  factory AppState() {
    return _instance;
  }
  
  AppState._internal();
  
  /// Display name of the currently signed-in user (empty when not signed in).
  String userName = '';

  /// Whether a user session is currently active.
  bool isLoggedIn = false;

  /// When `true`, all helpers read/write directly through [DatabaseHelper]
  /// (local SQLite mode).  When `false`, they delegate to [ApiService]
  /// (HTTP client mode connecting to a remote server).
  bool localDB = false;
}