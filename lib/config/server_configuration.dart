import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:utility_bills_manager/config/app_config.dart';
import 'package:utility_bills_manager/data/repositories/server_config_repository.dart';

import '../data/models/server_config.dart';
import '../utils/preferences.dart';

class ServerConfiguration {
  static ServerConfigRepository get _serverConfigRepo =>
      ServerConfigRepository();

  /// Loads server config from the database, then seeds it from `.env` values
  /// when needed:
  /// - Server mode: `.env` values are always authoritative (overwrites DB).
  /// - Client mode: seeds DB only on first run (no existing config).
  static Future<void> init() async {
    await Future.wait([
      _serverConfigRepo.reload(),
      Preferences.sharedPrefs,
    ]);
    await _seedFromEnv();
  }

  static Future<void> _seedFromEnv() async {
    if (AppConfig.mode == AppMode.client && _serverConfigRepo.config != null) {
      return;
    }

    final emailAddress = dotenv.env['EMAIL_ADDRESS'] ?? '';
    final emailPassword = dotenv.env['EMAIL_PASSWORD'] ?? '';
    final emailImapServer = dotenv.env['EMAIL_IMAP_SERVER'] ?? 'imap.gmail.com';
    final emailImapPort = int.tryParse(dotenv.env['EMAIL_IMAP_PORT'] ?? '') ?? 993;
    final rawSecure = dotenv.env['EMAIL_IMAP_SECURE'];
    final emailImapSecure = rawSecure == null || rawSecure.toLowerCase() == 'true';

    if (emailAddress.isEmpty && emailPassword.isEmpty) return;

    final config = ServerConfig(
      configId: _serverConfigRepo.config?.configId,
      emailAddress: emailAddress.isNotEmpty ? emailAddress : null,
      emailPassword: emailPassword.isNotEmpty ? emailPassword : null,
      emailImapServer: emailImapServer,
      emailImapPort: emailImapPort,
      emailImapSecure: emailImapSecure,
    );

    await _serverConfigRepo.update(config);
    updateServerConfigPreferences();
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

  static String get emailAddress =>
      _serverConfigRepo.config?.emailAddress ??
      Preferences.getString('EMAIL_ADDRESS') ??
      dotenv.env['EMAIL_ADDRESS'] ?? '';
  static Future<void> setEmailAddress(String address) async {
    await Preferences.setString('EMAIL_ADDRESS', address);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static String get emailPassword =>
      _serverConfigRepo.config?.emailPassword ??
      Preferences.getString('EMAIL_PASSWORD') ??
      dotenv.env['EMAIL_PASSWORD'] ?? '';
  static Future<void> setEmailPassword(String password) async {
    await Preferences.setString('EMAIL_PASSWORD', password);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static String get emailImapServer =>
      _serverConfigRepo.config?.emailImapServer ??
      Preferences.getString('EMAIL_IMAP_SERVER') ??
      dotenv.env['EMAIL_IMAP_SERVER'] ?? 'imap.gmail.com';
  static Future<void> setEmailImapServer(String server) async {
    await Preferences.setString('EMAIL_IMAP_SERVER', server);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static int get emailImapPort =>
      _serverConfigRepo.config?.emailImapPort ??
      Preferences.getInt('EMAIL_IMAP_PORT') ??
      int.tryParse(dotenv.env['EMAIL_IMAP_PORT'] ?? '') ?? 993;
  static Future<void> setEmailImapPort(int port) async {
    await Preferences.setInt('EMAIL_IMAP_PORT', port);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static bool get emailImapSecure {
    final stored = _serverConfigRepo.config?.emailImapSecure ??
        Preferences.getBool('EMAIL_IMAP_SECURE');
    if (stored != null) return stored;
    final raw = dotenv.env['EMAIL_IMAP_SECURE'];
    return raw == null || raw.toLowerCase() == 'true';
  }
  static Future<void> setEmailImapSecure(bool secure) async {
    await Preferences.setBool('EMAIL_IMAP_SECURE', secure);
    await _serverConfigRepo.update(serverConfigFromPreferences);
  }

  static DateTime get defaultEarliestDateTime =>
      DateTime.now().subtract(const Duration(days: 7));

  static String get earliestEmailDateEnv =>
      dotenv.env['EMAIL_EARLIEST_DATE'] ?? '';

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

  static Duration? get _emailSyncDelayDurationFromEnv {
    final secondsStr = dotenv.env['EMAIL_SYNC_DELAY_DURATION_SEC'] ?? '';
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

  static Duration? get _emailSyncIntervalFromEnv {
    final secondsStr = dotenv.env['EMAIL_SYNC_INTERVAL_SEC'] ?? '';
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
