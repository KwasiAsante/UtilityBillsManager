import 'package:shared_preferences/shared_preferences.dart';

class Preferences {
  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get sharedPrefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<bool> remove(String key) async {
    final success = await _prefs?.remove(key);
    return success ?? false;
  }
  static Future<bool> clear() async {
    final success = await _prefs?.clear();
    return success ?? false;
  }

  static bool? getBool(String key) => _prefs?.getBool(key);
  static Future<void> setBool(String key, bool? value) async {
    final prefs = await sharedPrefs;
    if (value != null) {
      await prefs.setBool(key, value);
    }
  }

  static double? getDouble(String key) => _prefs?.getDouble(key);
  static Future<void> setDouble(String key, double? value) async {
    final prefs = await sharedPrefs;
    if (value != null) {
      await prefs.setDouble(key, value);
    }
  }

  static int? getInt(String key) => _prefs?.getInt(key);
  static Future<void> setInt(String key, int? value) async {
    final prefs = await sharedPrefs;
    if (value != null) {
      await prefs.setInt(key, value);
    }
  }

  static String? getString(String key) => _prefs?.getString(key);
  static Future<void> setString(String key, String? value) async {
    final prefs = await sharedPrefs;
    if (value != null) {
      await prefs.setString(key, value);
    }
  }

  static List<String>? getStringList(String key) => _prefs?.getStringList(key);
  static Future<void> setStringList(String key, List<String>? value) async {
    final prefs = await sharedPrefs;
    if (value != null) {
      await prefs.setStringList(key, value);
    }
  }
}
