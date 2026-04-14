import 'package:uuid/uuid.dart';

import '../utils/preferences.dart';

/// Indicates whether the app should host its own SQLite server (`server`) or
/// connect to a remote one (`client`).  Controlled via the `APP_MODE`
/// dart-define.
enum AppMode { server, client }

extension AppModeExtension on AppMode {
  String get name {
    switch (this) {
      case AppMode.server:
        return 'server';
      case AppMode.client:
        return 'client';
    }
  }
}

/// Static configuration resolved from three sources (highest priority first):
/// 1. `assets/config/local_secrets.json` (loaded at startup via [init])
/// 2. `--dart-define` compile-time constants
/// 3. Hard-coded defaults
///
/// Provides [mode], [apiBaseUrl], and all email credential getters.
class AppConfig {
  /// Loads optional local secrets from a bundled asset and pre-warms
  /// the SharedPreferences instance.
  ///
  /// Call this once during startup (before reading any config).
  static Future<void> init() async {
    await Future.wait([Preferences.sharedPrefs]);
  }

  /// Parses the `APP_MODE` dart-define string into an [AppMode] enum value,
  /// defaulting to [AppMode.client] for any unrecognised value.
  static AppMode get mode {
    String? modeRaw = Preferences.getString('APP_MODE');
    if (modeRaw == null || modeRaw.isEmpty) {
      modeRaw = const String.fromEnvironment(
        'APP_MODE',
        defaultValue: 'client',
      );
    }

    final normalized = modeRaw.trim().toLowerCase();
    if (normalized == 'server') return AppMode.server;

    return AppMode.client;
  }

  static bool get isServer => mode == AppMode.server;
  static bool get isClient => mode == AppMode.client;
  static Future<void> setMode(AppMode newMode) async {
    await Preferences.setString('APP_MODE', newMode.name);
  }

  /// Base URL used by the app when it needs to call the API.
  ///
  /// - Server mode: defaults to localhost (self-hosted API)
  /// - Client mode: defaults to `API_BASE_URL` (connect to another host)
  static String get apiBaseUrl {
    if (mode == AppMode.server) {
      return 'http://127.0.0.1:8080';
    }

    String? apiUrl = Preferences.getString('API_BASE_URL');
    if (apiUrl != null && apiUrl.isNotEmpty) {
      return apiUrl;
    }

    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    );
  }
  static Future<void> setApiBaseUrl(String newUrl) async {
    await Preferences.setString('API_BASE_URL', newUrl);
  }

  static Future<String> get deviceId async {
    String? id = Preferences.getString('DEVICE_ID');
    if (id == null || id.isEmpty) {
      id = const String.fromEnvironment('DEVICE_ID', defaultValue: '');
      if (id.isNotEmpty) {
        await Preferences.setString('DEVICE_ID', id);
      }
    }

    if (id.isEmpty) {
      id = const Uuid().v4();
      await Preferences.setString('DEVICE_ID', id);
    }

    return id;
  }

  static const String _firebaseWebPushPublicKeyDefault =
      'BKSTBtACsIXdvpTa9VsMuv6b_kwJLkdmoGBWPY8_Y7aia8xaDj7Is0O1iV0MobqhuSa7W_yYQliUmPJP6dXIm0A';
  static Future<String> get firebaseWebPushPublicKey async {
    String? key = Preferences.getString('FIREBASE_WEB_PUSH_PUBLIC_KEY');
    if (key == null || key.isEmpty) {
      key = const String.fromEnvironment(
        'FIREBASE_WEB_PUSH_PUBLIC_KEY',
        defaultValue: '',
      );

      if (key.isEmpty) {
        key = _firebaseWebPushPublicKeyDefault;
        await Preferences.setString('FIREBASE_WEB_PUSH_PUBLIC_KEY', key);
      }
    }

    if (key.isEmpty) {
      key = _firebaseWebPushPublicKeyDefault;
      await Preferences.setString('FIREBASE_WEB_PUSH_PUBLIC_KEY', key);
    }

    return key;
  }
}
