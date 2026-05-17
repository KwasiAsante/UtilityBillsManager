import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const _tokenKey = 'AUTH_TOKEN';
  static const _emailKey = 'AUTH_EMAIL';

  String? _token;
  String? _email;
  bool _pendingUnauthorized = false;

  String? get token => _token;
  String? get email => _email;
  bool get isLoggedIn => _token != null;
  bool get pendingUnauthorized => _pendingUnauthorized;

  void clearUnauthorized() {
    _pendingUnauthorized = false;
    notifyListeners();
  }

  void notifyUnauthorized() {
    if (_pendingUnauthorized) return;
    _pendingUnauthorized = true;
    notifyListeners();
  }

  /// Restores session from SharedPreferences and registers the 401/403 callback.
  /// Call once at app startup after [ApiService.configure].
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _email = prefs.getString(_emailKey);
    if (_token != null) {
      ApiService.setAuthToken(_token);
    }
    ApiService.onUnauthorized = notifyUnauthorized;
    notifyListeners();
  }

  /// Signs in with [email] and [password].
  /// Returns null on success, or an error string on failure.
  Future<String?> login(String email, String password) async {
    final session = await ApiService.auth().login(email, password);
    if (session == null) return 'Invalid email or password';
    await _persistSession(session.token, email);
    return null;
  }

  /// Registers with [email] and [password], then auto-logs in on success.
  /// Returns null on success, or an error string on failure.
  Future<String?> register(String email, String password) async {
    final result = await ApiService.auth().register(email, password);
    if (result != 'OK') return result;
    return login(email, password);
  }

  /// Signs out — revokes the server session and clears local state.
  Future<void> logout() async {
    try {
      await ApiService.auth().logout();
    } finally {
      await _clearSession();
    }
  }

  Future<void> _persistSession(String token, String email) async {
    _token = token;
    _email = email;
    ApiService.setAuthToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_emailKey, email);
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _token = null;
    _email = null;
    ApiService.setAuthToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_emailKey);
    notifyListeners();
  }
}
