/// Client-side representation of the server's `Configuration` model.
///
/// Stores the IMAP email credentials and sync scheduling parameters managed by
/// the remote utility-bills server.  All fields are nullable — the server owns
/// the defaults (populated from its own `AppConfig` / `local_secrets.json`).
///
/// Serialised to / from the same JSON shape as the server's `Configuration`
/// so that [ConfigApiService] and [DatabaseHelper] can share one codec.
class ServerConfig {
  /// SQLite auto-increment row id (local DB only; null in API mode).
  final int? id;

  /// Stable UUID identifier for this configuration record.
  final String? configId;

  /// IMAP account email address used to log in to the mail server.
  String? emailAddress;

  /// IMAP account password (or app-specific password for Gmail).
  String? emailPassword;

  /// Hostname of the IMAP server (e.g. `imap.gmail.com`).
  String? emailImapServer;

  /// Port of the IMAP server (typically 993 for SSL/TLS).
  int? emailImapPort;

  /// Whether to use a secure (TLS) connection to the IMAP server.
  bool? emailImapSecure;

  /// Only emails received on or after this date will be fetched.
  DateTime? emailEarliestDate;

  /// How long to wait after server startup before performing the first sync.
  Duration? emailSyncDelayDuration;

  /// How frequently the email scheduler repeats after the initial sync.
  Duration? emailSyncInterval;

  ServerConfig({
    this.id,
    this.configId,
    this.emailAddress,
    this.emailPassword,
    this.emailImapServer,
    this.emailImapPort,
    this.emailImapSecure,
    this.emailEarliestDate,
    this.emailSyncDelayDuration,
    this.emailSyncInterval,
  });

  /// Serialises this configuration to a flat map for SQLite insertion or HTTP
  /// request bodies.
  ///
  /// [emailImapSecure] is stored as an integer (1/0) for SQLite compatibility.
  /// [Duration] fields are stored as their total seconds.
  Map<String, dynamic> toJson() {
    return {
      'configId': configId,
      'emailAddress': emailAddress,
      'emailPassword': emailPassword,
      'emailImapServer': emailImapServer,
      'emailImapPort': emailImapPort,
      'emailImapSecure': emailImapSecure != null && emailImapSecure! ? 1 : 0,
      'emailEarliestDate': emailEarliestDate?.toIso8601String(),
      'emailSyncDelayDuration': emailSyncDelayDuration?.inSeconds,
      'emailSyncInterval': emailSyncInterval?.inSeconds,
    };
  }

  /// Deserializes a [ServerConfig] from a SQLite row or API JSON map.
  ///
  /// [Duration] fields are stored as integers (seconds) and reconstructed here.
  /// [emailImapSecure] tolerates both integer (0/1) and boolean string forms.
  factory ServerConfig.fromJson(Map<String, dynamic> map) {
    bool? parseSecure(dynamic raw) {
      if (raw == null) return null;
      final parsed = bool.tryParse(raw.toString());
      if (parsed != null) return parsed;
      return raw == 1;
    }

    return ServerConfig(
      id: map['id'] as int?,
      configId: map['configId'] as String?,
      emailAddress: map['emailAddress'] as String?,
      emailPassword: map['emailPassword'] as String?,
      emailImapServer: map['emailImapServer'] as String?,
      emailImapPort: map['emailImapPort'] as int?,
      emailImapSecure: parseSecure(map['emailImapSecure']),
      emailEarliestDate: map['emailEarliestDate'] != null
          ? DateTime.tryParse(map['emailEarliestDate'] as String)
          : null,
      emailSyncDelayDuration: map['emailSyncDelayDuration'] != null
          ? Duration(seconds: map['emailSyncDelayDuration'] as int)
          : null,
      emailSyncInterval: map['emailSyncInterval'] != null
          ? Duration(seconds: map['emailSyncInterval'] as int)
          : null,
    );
  }
}
