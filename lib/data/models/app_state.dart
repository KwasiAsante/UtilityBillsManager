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