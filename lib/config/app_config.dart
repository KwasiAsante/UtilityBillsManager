import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/models/app_configuration.dart';
import '../helpers/configuration/app_config_helper.dart';
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
  /// In-memory cache populated by [load]. All synchronous getters read from
  /// this cache after startup so the DB is never hit on the hot path.
  static AppConfiguration? _appConfig;

  /// Loads optional local secrets from a bundled asset and pre-warms
  /// the SharedPreferences instance.
  ///
  /// Call this once during startup (before reading any config).
  static Future<void> init() async {
    await Future.wait([Preferences.sharedPrefs]);
  }

  /// Reads [AppConfiguration] from SQLite into [_appConfig].
  ///
  /// Must be called after the database is open and before [apiBaseUrl] is
  /// first read. In `main.dart` this runs immediately after
  /// `await DatabaseHelper().database`.
  static Future<void> load() async {
    final result = await AppConfigHelper().readConfiguration();
    if (result.isSuccess) {
      _appConfig = result.data;
    }
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

  static const String _defaultApiBaseUrl = 'https://kwasi-utilitybills.duckdns.org';

  /// Base URL used by the app when it needs to call the API.
  ///
  /// Resolution order (highest priority first):
  /// 1. [_appConfig.baseWebAPI] — SQLite-backed, reliable across sessions
  /// 2. SharedPreferences `API_BASE_URL` — legacy fallback
  /// 3. `dart-define` `API_BASE_URL`
  /// 4. Hardcoded default ([_defaultApiBaseUrl])
  ///
  /// - Server mode always returns localhost regardless of stored value.
  static String get apiBaseUrl {
    if (mode == AppMode.server) {
      return 'http://127.0.0.1:8080';
    }

    // 1. SQLite-backed cache (survives browser/app restarts on all platforms)
    if (_appConfig?.baseWebAPI != null &&
        _appConfig!.baseWebAPI!.isNotEmpty) {
      return _appConfig!.baseWebAPI!;
    }

    // 2. SharedPreferences fallback (legacy)
    String? apiUrl = Preferences.getString('API_BASE_URL');

    if (apiUrl != null && apiUrl.isNotEmpty) {
      if (apiUrl == 'http://192.168.2.172:8080' &&
          (defaultTargetPlatform != TargetPlatform.android ||
              defaultTargetPlatform != TargetPlatform.iOS)) {
        apiUrl = 'http://127.0.0.1:8080';
      }
      return apiUrl;
    }

    // 3. dart-define / hardcoded default
    apiUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _defaultApiBaseUrl,
    );

    if (apiUrl == 'http://192.168.2.172:8080' &&
        (defaultTargetPlatform != TargetPlatform.android ||
        defaultTargetPlatform != TargetPlatform.iOS)) {
      apiUrl = 'http://127.0.0.1:8080';
    }

    return apiUrl;
  }
  static Future<void> setApiBaseUrl(String newUrl) async {
    final config = AppConfiguration(
      configId: _appConfig?.configId ?? const Uuid().v4(),
      baseWebAPI: newUrl,
      messageTemplate: _appConfig?.messageTemplate,
    );
    await AppConfigHelper().saveConfiguration(config);
    _appConfig = config;
    // Keep SharedPreferences in sync for any legacy consumers.
    await Preferences.setString('API_BASE_URL', newUrl);
  }

  /// Template used to generate per-rentor bill summary messages.
  ///
  /// Falls back to [AppConfiguration.defaultMessageTemplate] when no custom
  /// template has been saved.
  static String get messageTemplate {
    final stored = _appConfig?.messageTemplate;
    if (stored != null && stored.isNotEmpty) return stored;
    return AppConfiguration.defaultMessageTemplate;
  }

  static Future<void> setMessageTemplate(String template) async {
    final config = AppConfiguration(
      configId: _appConfig?.configId ?? const Uuid().v4(),
      baseWebAPI: _appConfig?.baseWebAPI,
      messageTemplate: template,
    );
    await AppConfigHelper().saveConfiguration(config);
    _appConfig = config;
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
