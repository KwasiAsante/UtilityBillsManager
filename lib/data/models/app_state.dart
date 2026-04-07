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
  
  // Your shared variables
  String userName = '';
  bool isLoggedIn = false;
  bool localDB = false;
}