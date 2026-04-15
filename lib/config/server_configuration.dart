import 'dart:convert';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:utility_bills_manager/config/app_config.dart';
import 'package:utility_bills_manager/data/repositories/server_config_repository.dart';

import '../data/models/server_config.dart';
import '../utils/app_logger.dart';
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

/// Loads and decrypts secrets from a bundled JSON asset.
///
/// String values prefixed with `enc:` are decrypted during [loadFromAsset]
/// using AES-256-GCM with the key supplied via
/// `--dart-define=SECRETS_KEY=<32-char-key>`. Non-string fields (int, bool)
/// are stored in plaintext and never touched.
///
/// Encrypt values with the bundled script:
///   dart run scripts/encrypt_secrets.dart --key=<32-char-key>
///
/// Example encrypted `local_secrets.json`:
/// ```json
/// {
///   "EMAIL_ADDRESS": "enc:BASE64_NONCE.BASE64_CIPHERTEXT_MAC",
///   "EMAIL_PASSWORD": "enc:BASE64_NONCE.BASE64_CIPHERTEXT_MAC",
///   "EMAIL_IMAP_SERVER": "enc:BASE64_NONCE.BASE64_CIPHERTEXT_MAC",
///   "EMAIL_IMAP_PORT": 993,
///   "EMAIL_IMAP_SECURE": true
/// }
/// ```
class _LocalSecrets {
  static Map<String, dynamic> _cache = <String, dynamic>{};
  static bool _loaded = false;

  // Key must be exactly 32 characters (AES-256).
  // Supplied at build time: --dart-define=SECRETS_KEY=<32-char-key>
  static const _secretsKey = String.fromEnvironment(
    'SECRETS_KEY',
    defaultValue: '',
  );

  /// Loads the JSON asset and decrypts all `enc:`-prefixed string values in
  /// place. After this call, [_cache] contains only plaintext values and all
  /// getter methods can remain synchronous.
  static Future<void> loadFromAsset(String assetPath) async {
    if (_loaded) return;
    try {
      final contents = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(contents);
      Map<String, dynamic> raw;
      if (decoded is Map<String, dynamic>) {
        raw = decoded;
      } else if (decoded is Map) {
        raw = decoded.map((k, v) => MapEntry(k.toString(), v));
      } else {
        raw = {};
      }
      _cache = await _decryptAll(raw);
    } catch (_) {
      _cache = {};
    } finally {
      _loaded = true;
    }
  }

  /// Walks every entry; decrypts any `enc:`-prefixed string value, leaves
  /// everything else untouched.
  static Future<Map<String, dynamic>> _decryptAll(
      Map<String, dynamic> raw) async {
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.value is String &&
          (entry.value as String).startsWith('enc:')) {
        result[entry.key] =
            await _decrypt(entry.value as String) ?? entry.value;
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// Decrypts one `enc:<base64-nonce>.<base64-ciphertext+mac>` string.
  /// Uses AES-256-GCM (authenticated encryption).
  static Future<String?> _decrypt(String value) async {
    if (_secretsKey.isEmpty) {
      AppLogger().w(
          '[LocalSecrets] SECRETS_KEY dart-define not set; cannot decrypt secrets');
      return null;
    }
    if (_secretsKey.length != 32) {
      AppLogger().w(
          '[LocalSecrets] SECRETS_KEY must be exactly 32 characters (got ${_secretsKey.length})');
      return null;
    }
    try {
      final payload = value.substring(4); // strip "enc:"
      final dot = payload.indexOf('.');
      if (dot == -1) return null;

      final nonce = base64Decode(payload.substring(0, dot));
      final cipherAndMac = base64Decode(payload.substring(dot + 1));

      // Last 16 bytes are the GCM authentication tag.
      final ciphertext = cipherAndMac.sublist(0, cipherAndMac.length - 16);
      final mac = cipherAndMac.sublist(cipherAndMac.length - 16);

      final algorithm = crypto.AesGcm.with256bits();
      final secretKey = await algorithm.newSecretKeyFromBytes(
        _secretsKey.codeUnits,
      );
      final plainBytes = await algorithm.decrypt(
        crypto.SecretBox(ciphertext, nonce: nonce, mac: crypto.Mac(mac)),
        secretKey: secretKey,
      );
      return String.fromCharCodes(plainBytes);
    } catch (e) {
      AppLogger().e('[LocalSecrets] Decryption failed: $e');
      return null;
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
