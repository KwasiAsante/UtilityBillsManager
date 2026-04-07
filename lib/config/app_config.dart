import 'dart:convert';

import 'package:flutter/services.dart';

enum AppMode { server, client }

class AppConfig {
  /// Loads optional local secrets from a bundled asset.
  ///
  /// Call this once during startup (before reading any config).
  static Future<void> init({
    String assetPath = 'assets/config/local_secrets.json',
  }) =>
      _LocalSecrets.loadFromAsset(assetPath);

  static const String _modeRaw = String.fromEnvironment(
    'APP_MODE',
    defaultValue: 'server',
  );

  static AppMode get mode {
    final normalized = _modeRaw.trim().toLowerCase();
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
      const String.fromEnvironment(
        'EMAIL_ADDRESS',
        defaultValue: '',
      );

  static String get emailPassword =>
      _LocalSecrets.getString('EMAIL_PASSWORD') ??
      const String.fromEnvironment(
        'EMAIL_PASSWORD',
        defaultValue: '',
      );

  static String get emailImapServer =>
      _LocalSecrets.getString('EMAIL_IMAP_SERVER') ??
      const String.fromEnvironment(
        'EMAIL_IMAP_SERVER',
        defaultValue: 'imap.gmail.com',
      );

  static int get emailImapPort =>
      _LocalSecrets.getInt('EMAIL_IMAP_PORT') ??
      const int.fromEnvironment(
        'EMAIL_IMAP_PORT',
        defaultValue: 993,
      );

  static bool get emailImapSecure =>
      _LocalSecrets.getBool('EMAIL_IMAP_SECURE') ??
      const bool.fromEnvironment(
        'EMAIL_IMAP_SECURE',
        defaultValue: true,
      );

  static DateTime get defaultEarliestDateTime => DateTime.now().subtract(const Duration(days: 60));
  static String get earliestEmailDateEnv =>
      const String.fromEnvironment('EMAIL_EARLIEST_DATE', defaultValue: '');
  static DateTime get emailEarliestDate =>
      _LocalSecrets.getDateTime('EMAIL_EARLIEST_DATE') ??
          DateTime.tryParse(earliestEmailDateEnv) ??
          defaultEarliestDateTime;
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
        _cache = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
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

