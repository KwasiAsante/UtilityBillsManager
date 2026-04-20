/// Local app-level configuration persisted in the SQLite `app_configuration`
/// table. Currently holds the API base URL; additional fields may be added
/// as the app grows.
class AppConfiguration {
  /// SQLite auto-increment row id (never included in [toJson]).
  final int? id;

  /// Stable UUID identifier for this configuration record.
  final String? configId;

  /// Base URL used when making API calls to the remote server.
  String? baseWebAPI;

  AppConfiguration({this.id, this.configId, this.baseWebAPI});

  /// Serialises to a flat map for SQLite insertion.
  ///
  /// Does NOT include [id] — SQLite auto-increments it on insert.
  Map<String, dynamic> toJson() => {
        'configId': configId,
        'baseWebAPI': baseWebAPI,
      };

  /// Deserialises from a SQLite row map.
  factory AppConfiguration.fromJson(Map<String, dynamic> map) =>
      AppConfiguration(
        id: map['id'] as int?,
        configId: map['configId'] as String?,
        baseWebAPI: map['baseWebAPI'] as String?,
      );
}
