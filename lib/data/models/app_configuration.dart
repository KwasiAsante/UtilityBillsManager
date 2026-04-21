/// Local app-level configuration persisted in the SQLite `app_configuration`
/// table.
class AppConfiguration {
  /// Default template used when no custom template has been saved.
  ///
  /// Available placeholders: `{{greeting}}`, `{{firstName}}`, `{{fullName}}`,
  /// `{{billSummary}}`.
  static const String defaultMessageTemplate =
      '{{greeting}} {{firstName}}, {{billSummary}}';

  /// SQLite auto-increment row id (never included in [toJson]).
  final int? id;

  /// Stable UUID identifier for this configuration record.
  final String? configId;

  /// Base URL used when making API calls to the remote server.
  String? baseWebAPI;

  /// Template used to generate per-rentor bill summary messages.
  ///
  /// Supports `{{greeting}}`, `{{firstName}}`, `{{fullName}}`, and
  /// `{{billSummary}}` placeholders.  `null` means use [defaultMessageTemplate].
  String? messageTemplate;

  AppConfiguration({this.id, this.configId, this.baseWebAPI, this.messageTemplate});

  /// Serialises to a flat map for SQLite insertion.
  ///
  /// Does NOT include [id] — SQLite auto-increments it on insert.
  Map<String, dynamic> toJson() => {
        'configId': configId,
        'baseWebAPI': baseWebAPI,
        'messageTemplate': messageTemplate,
      };

  /// Deserialises from a SQLite row map.
  factory AppConfiguration.fromJson(Map<String, dynamic> map) =>
      AppConfiguration(
        id: map['id'] as int?,
        configId: map['configId'] as String?,
        baseWebAPI: map['baseWebAPI'] as String?,
        messageTemplate: map['messageTemplate'] as String?,
      );
}
