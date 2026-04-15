import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:utility_bills_manager/config/app_config.dart';
import 'package:utility_bills_manager/data/repositories/server_config_repository.dart';

import '../data/models/server_config.dart';
import '../utils/preferences.dart';

class ServerConfiguration {
  static ServerConfigRepository get _serverConfigRepo =>
      ServerConfigRepository();

  /// Loads optional local secrets from a bundled asset and pre-warms
  /// the SharedPreferences instance.
  ///
  /// Call this once during startup (before reading any config).
  static Future<void> init({String? assetPath = "assets/config/local_secrets.json"}) async {
    await Future.wait([
      _loadServerConfig(assetPath: assetPath),
      Preferences.sharedPrefs,
    ]);
  }

  static Future<void> _loadServerConfig({
    String? assetPath = "assets/config/local_secrets.json",
  }) async {
    if (AppConfig.mode == AppMode.server) {
      await _LocalSecrets.loadFromAsset(assetPath!);
      _updateServerConfigPreferencesFromLocalSecrets();
      await _serverConfigRepo.update(_serverConfigFromLocalSecrets);
    } else {
      await _serverConfigRepo.reload();
      if (_serverConfigRepo.config == null) {
        await _LocalSecrets.loadFromAsset(assetPath!);
        _updateServerConfigPreferencesFromLocalSecrets();
        await _serverConfigRepo.update(_serverConfigFromLocalSecrets);
      }
    }
  }

  static void updateServerConfigPreferences() {
    ServerConfig? config = _serverConfigRepo.config;
    if (config != null) {
      Preferences.setString('EMAIL_ADDRESS', config.emailAddress);
      Preferences.setString('EMAIL_PASSWORD', config.emailPassword);
      Preferences.setString('EMAIL_IMAP_SERVER', config.emailImapServer);
      Preferences.setInt('EMAIL_IMAP_PORT', config.emailImapPort);
      Preferences.setBool('EMAIL_IMAP_SECURE', config.emailImapSecure);
      Preferences.setString(
        'EMAIL_EARLIEST_DATE',
        config.emailEarliestDate?.toIso8601String(),
      );
    }
  }

  static void _updateServerConfigPreferencesFromLocalSecrets() {
    Preferences.setString(
      'EMAIL_ADDRESS',
      _LocalSecrets.getString('EMAIL_ADDRESS') ?? '',
    );
    Preferences.setString(
      'EMAIL_PASSWORD',
      _LocalSecrets.getString('EMAIL_PASSWORD') ?? '',
    );
    Preferences.setString(
      'EMAIL_IMAP_SERVER',
      _LocalSecrets.getString('EMAIL_IMAP_SERVER') ?? '',
    );
    Preferences.setInt(
      'EMAIL_IMAP_PORT',
      _LocalSecrets.getInt('EMAIL_IMAP_PORT') ?? 993,
    );
    Preferences.setBool(
      'EMAIL_IMAP_SECURE',
      _LocalSecrets.getBool('EMAIL_IMAP_SECURE') ?? true,
    );
    final earliestDate = _LocalSecrets.getDateTime('EMAIL_EARLIEST_DATE');
    if (earliestDate != null) {
      Preferences.setString(
        'EMAIL_EARLIEST_DATE',
        earliestDate.toIso8601String(),
      );
    }
  }

  static ServerConfig get serverConfigFromPreferences {
    return ServerConfig(
      configId: _serverConfigRepo.config?.configId,
      emailAddress: Preferences.getString('EMAIL_ADDRESS'),
      emailPassword: Preferences.getString('EMAIL_PASSWORD'),
      emailImapServer: Preferences.getString('EMAIL_IMAP_SERVER'),
      emailImapPort: Preferences.getInt('EMAIL_IMAP_PORT'),
      emailImapSecure: Preferences.getBool('EMAIL_IMAP_SECURE'),
      emailEarliestDate: DateTime.tryParse(Preferences.getString('EMAIL_EARLIEST_DATE') ?? ''),
      emailSyncDelayDuration: _emailSyncDelayDurationFromPreferences,
      emailSyncInterval: _emailSyncIntervalFromPreferences,
    );
  }

  static ServerConfig get _serverConfigFromLocalSecrets {
    return ServerConfig(
      configId: _serverConfigRepo.config?.configId,
      emailAddress: _LocalSecrets.getString('EMAIL_ADDRESS'),
      emailPassword: _LocalSecrets.getString('EMAIL_PASSWORD'),
      emailImapServer: _LocalSecrets.getString('EMAIL_IMAP_SERVER'),
      emailImapPort: _LocalSecrets.getInt('EMAIL_IMAP_PORT'),
      emailImapSecure: _LocalSecrets.getBool('EMAIL_IMAP_SECURE'),
      emailEarliestDate: _LocalSecrets.getDateTime('EMAIL_EARLIEST_DATE'),
    );
  }

  /// Email configuration.
  /// Order of precedence:
  /// 1. `local_secrets.json` file values
  /// 2. `--dart-define` values
  /// 3. Safe defaults
  static String get emailAddress =>
      _serverConfigRepo.config?.emailAddress ??
      Preferences.getString('EMAIL_ADDRESS') ??
      const String.fromEnvironment('EMAIL_ADDRESS', defaultValue: '');
  static Future<void> setEmailAddress(String address) async {
    await Preferences.setString('EMAIL_ADDRESS', address);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static String get emailPassword =>
      _serverConfigRepo.config?.emailPassword ??
      Preferences.getString('EMAIL_PASSWORD') ??
      const String.fromEnvironment('EMAIL_PASSWORD', defaultValue: '');
  static Future<void> setEmailPassword(String password) async {
    await Preferences.setString('EMAIL_PASSWORD', password);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static String get emailImapServer =>
      _serverConfigRepo.config?.emailImapServer ??
      Preferences.getString('EMAIL_IMAP_SERVER') ??
      const String.fromEnvironment(
        'EMAIL_IMAP_SERVER',
        defaultValue: 'imap.gmail.com',
      );
  static Future<void> setEmailImapServer(String server) async {
    await Preferences.setString('EMAIL_IMAP_SERVER', server);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static int get emailImapPort =>
      _serverConfigRepo.config?.emailImapPort ??
      Preferences.getInt('EMAIL_IMAP_PORT') ??
      const int.fromEnvironment('EMAIL_IMAP_PORT', defaultValue: 993);
  static Future<void> setEmailImapPort(int port) async {
    await Preferences.setInt('EMAIL_IMAP_PORT', port);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static bool get emailImapSecure =>
      _serverConfigRepo.config?.emailImapSecure ??
      Preferences.getBool('EMAIL_IMAP_SECURE') ??
      const bool.fromEnvironment('EMAIL_IMAP_SECURE', defaultValue: true);
  static Future<void> setEmailImapSecure(bool secure) async {
    await Preferences.setBool('EMAIL_IMAP_SECURE', secure);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  /// Fallback oldest email date used when no `EMAIL_EARLIEST_DATE` is configured
  /// (7 days ago from today).
  static DateTime get defaultEarliestDateTime =>
      DateTime.now().subtract(const Duration(days: 7));

  static String get earliestEmailDateEnv =>
      const String.fromEnvironment('EMAIL_EARLIEST_DATE', defaultValue: '');

  static String? get earliestEmailDateSharedPref =>
      Preferences.getString('EMAIL_EARLIEST_DATE');

  static DateTime get emailEarliestDate =>
      _serverConfigRepo.config?.emailEarliestDate ??
      DateTime.tryParse(earliestEmailDateSharedPref ?? '') ??
      DateTime.tryParse(earliestEmailDateEnv) ??
      defaultEarliestDateTime;
  static Future<void> setEmailEarliestDate(DateTime date) async {
    await Preferences.setString('EMAIL_EARLIEST_DATE', date.toIso8601String());
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  /// Email sync delay duration (how long to wait after server startup before performing the first sync).
  static Duration? get _emailSyncDelayDurationFromEnv {
    final secondsStr = const String.fromEnvironment(
      'EMAIL_SYNC_DELAY_DURATION_SEC',
      defaultValue: '',
    );
    if (secondsStr.isEmpty) return null;
    final seconds = int.tryParse(secondsStr);
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }

  static Duration? get _emailSyncDelayDurationFromPreferences {
    final seconds = Preferences.getInt('EMAIL_SYNC_DELAY_DURATION_SEC');
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }

  static Duration get emailSyncDelayDuration =>
      _serverConfigRepo.config != null &&
              _serverConfigRepo.config!.emailSyncDelayDuration != null
          ? _serverConfigRepo.config!.emailSyncDelayDuration!
          : _emailSyncDelayDurationFromPreferences ??
          _emailSyncDelayDurationFromEnv ??
          const Duration(seconds: 30);
  static Future<void> setEmailSyncDelayDuration(Duration duration) async {
    await Preferences.setInt(
      'EMAIL_SYNC_DELAY_DURATION_SEC',
      duration.inSeconds,
    );
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  /// Email sync interval (how frequently the email scheduler repeats after the initial sync).
  static Duration? get _emailSyncIntervalFromEnv {
    final secondsStr = const String.fromEnvironment(
      'EMAIL_SYNC_INTERVAL_SEC',
      defaultValue: '',
    );
    if (secondsStr.isEmpty) return null;
    final seconds = int.tryParse(secondsStr);
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }

  static Duration? get _emailSyncIntervalFromPreferences {
    final seconds = Preferences.getInt('EMAIL_SYNC_INTERVAL_SEC');
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }

  static Duration get emailSyncInterval =>
      _serverConfigRepo.config != null &&
              _serverConfigRepo.config!.emailSyncInterval != null
          ? _serverConfigRepo.config!.emailSyncInterval!
          : _emailSyncIntervalFromPreferences ??
          _emailSyncIntervalFromEnv ??
          const Duration(minutes: 15);
  static Future<void> setEmailSyncInterval(Duration interval) async {
    await Preferences.setInt(
      'EMAIL_SYNC_INTERVAL_SEC',
      interval.inSeconds,
    );
    await _serverConfigRepo.update(serverConfigFromPreferences);
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
