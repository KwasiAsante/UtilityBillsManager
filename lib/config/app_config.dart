import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Indicates whether the app should host its own SQLite server (`server`) or
/// connect to a remote one (`client`).  Controlled via the `APP_MODE`
/// dart-define.
enum AppMode { server, client }

/// Static configuration resolved from three sources (highest priority first):
/// 1. `assets/config/local_secrets.json` (loaded at startup via [init])
/// 2. `--dart-define` compile-time constants
/// 3. Hard-coded defaults
///
/// Provides [mode], [apiBaseUrl], and all email credential getters.
class AppConfig {
  /// Loads optional local secrets from a bundled asset.
  ///
  /// Call this once during startup (before reading any config).
  static Future<void> init({
    String assetPath = 'assets/config/local_secrets.json',
  }) => _LocalSecrets.loadFromAsset(assetPath);

  static bool? _getBoolFromSharedPreferences(String key) {
    bool? value;
    SharedPreferences.getInstance().then((prefs) {
      value = prefs.getBool(key);
    });
    return value;
  }

  static double? _getDoubleFromSharedPreferences(String key) {
    double? value;
    SharedPreferences.getInstance().then((prefs) {
      value = prefs.getDouble(key);
    });
    return value;
  }

  static int? _getIntFromSharedPreferences(String key) {
    int? value;
    SharedPreferences.getInstance().then((prefs) {
      value = prefs.getInt(key);
    });
    return value;
  }

  static String? _getStringFromSharedPreferences(String key) {
    String? value = '';
    SharedPreferences.getInstance().then((prefs) {
      value = prefs.getString(key);
    });
    return value;
  }

  static List<String>? _getStringListFromSharedPreferences(String key) {
    List<String>? value;
    SharedPreferences.getInstance().then((prefs) {
      value = prefs.getStringList(key);
    });
    return value;
  }

  /// Parses the `APP_MODE` dart-define string into an [AppMode] enum value,
  /// defaulting to [AppMode.server] for any unrecognised value.
  static AppMode get mode {
    String? modeRaw = _getStringFromSharedPreferences('APP_MODE');
    if (modeRaw == null || modeRaw.isEmpty) {
      modeRaw = String.fromEnvironment('APP_MODE', defaultValue: 'client');
    }

    final normalized = modeRaw.trim().toLowerCase();
    if (normalized == 'client') return AppMode.client;

    return AppMode.server;
  }

  /// Base URL used by the app when it needs to call the API.
  ///
  /// - Server mode: defaults to localhost (self-hosted API)
  /// - Client mode: defaults to `API_BASE_URL` (connect to another host)
  static String get apiBaseUrl {
    if (mode == AppMode.server) {
      return 'http://127.0.0.1:8080';
    }

    String? apiUrl = _getStringFromSharedPreferences('API_BASE_URL');
    if (apiUrl != null && apiUrl.isNotEmpty) {
      return apiUrl;
    }

    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    );
  }

  /// Email configuration.
  /// Order of precedence:
  /// 1. `local_secrets.json` file values
  /// 2. `--dart-define` values
  /// 3. Safe defaults
  static String get emailAddress =>
      _LocalSecrets.getString('EMAIL_ADDRESS') ??
      _getStringFromSharedPreferences('EMAIL_ADDRESS') ??
      const String.fromEnvironment('EMAIL_ADDRESS', defaultValue: '');

  static String get emailPassword =>
      _LocalSecrets.getString('EMAIL_PASSWORD') ??
      _getStringFromSharedPreferences('EMAIL_PASSWORD') ??
      const String.fromEnvironment('EMAIL_PASSWORD', defaultValue: '');

  static String get emailImapServer =>
      _LocalSecrets.getString('EMAIL_IMAP_SERVER') ??
      _getStringFromSharedPreferences('EMAIL_IMAP_SERVER') ??
      const String.fromEnvironment(
        'EMAIL_IMAP_SERVER',
        defaultValue: 'imap.gmail.com',
      );

  static int get emailImapPort =>
      _LocalSecrets.getInt('EMAIL_IMAP_PORT') ??
      _getIntFromSharedPreferences('EMAIL_IMAP_PORT') ??
      const int.fromEnvironment('EMAIL_IMAP_PORT', defaultValue: 993);

  static bool get emailImapSecure =>
      _LocalSecrets.getBool('EMAIL_IMAP_SECURE') ??
      _getBoolFromSharedPreferences('EMAIL_IMAP_SECURE') ??
      const bool.fromEnvironment('EMAIL_IMAP_SECURE', defaultValue: true);

  /// Fallback oldest email date used when no `EMAIL_EARLIEST_DATE` is configured
  /// (60 days ago from today).
  static DateTime get defaultEarliestDateTime =>
      DateTime.now().subtract(const Duration(days: 60));

  static String get earliestEmailDateEnv =>
      const String.fromEnvironment('EMAIL_EARLIEST_DATE', defaultValue: '');

  static String? get earliestEmailDateSharedPref =>
      _getStringFromSharedPreferences('EMAIL_EARLIEST_DATE');

  static DateTime get emailEarliestDate =>
      _LocalSecrets.getDateTime('EMAIL_EARLIEST_DATE') ??
      DateTime.tryParse(earliestEmailDateSharedPref ?? '') ??
      DateTime.tryParse(earliestEmailDateEnv) ??
      defaultEarliestDateTime;

  static String get deviceId {
    String? id = _getStringFromSharedPreferences('DEVICE_ID');
    if (id == null || id.isEmpty) {
      id = String.fromEnvironment('DEVICE_ID', defaultValue: '');
    }

    if (id.isEmpty) {
      id = const Uuid().v4();
      deviceId = id; // persist for future runs
    }

    return id;
  }

  static set deviceId(String value) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('DEVICE_ID', value);
    });
  }
}

/// Loads optional local secrets from a JSON file that is NOT bundled
/// into your app (unless you explicitly package it yourself).
///
/// Example `local_secrets.json` (kept out of git and builds):
/// {
///   "EMAIL_ADDRESS": "you@example.com",
///   "EMAIL_PASSWORD": "app-password",
///   "EMAIL_IMAP_SERVER": "imap.gmail.com",
///   "EMAIL_IMAP_PORT": 993,
///   "EMAIL_IMAP_SECURE": true
/// }
class _LocalSecrets {
  static Map<String, dynamic> _cache = <String, dynamic>{};
  static bool _loaded = false;

  static Future<void> loadFromAsset(String assetPath) async {
    if (_loaded) return;
    try {
      final contents = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(contents);
      if (decoded is Map<String, dynamic>) {
        _cache = decoded;
      } else if (decoded is Map) {
        _cache = decoded.map((key, value) => MapEntry(key.toString(), value));
      } else {
        _cache = <String, dynamic>{};
      }
    } catch (_) {
      _cache = <String, dynamic>{};
    } finally {
      _loaded = true;
    }
  }

  static Map<String, dynamic> get _data => _cache;

  static String? getString(String key) {
    final value = _data[key];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static int? getInt(String key) {
    final value = _data[key];
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static bool? getBool(String key) {
    final value = _data[key];
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return null;
  }

  static DateTime? getDateTime(String key) {
    final value = _data[key];
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
