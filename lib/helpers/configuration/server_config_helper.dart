import '../database/database_helper.dart';
import '../../config/app_config.dart';
import '../../data/models/result.dart';
import '../../data/models/server_config.dart';
import '../../services/api/api_service.dart';

/// Singleton service layer for server configuration persistence.
///
/// Routes every operation to either the local SQLite [DatabaseHelper] (when
/// [AppConfig.mode] == [AppMode.server]) or the remote [ConfigApiService].
///
/// The local `configuration` table holds at most one row; [createConfiguration]
/// clears the table before inserting so stale records are never left behind.
class ServerConfigHelper {
  static final ServerConfigHelper _instance = ServerConfigHelper._internal();

  factory ServerConfigHelper() => _instance;

  ServerConfigHelper._internal();

  /// Returns the [DatabaseHelper] singleton. Only use when
  /// [AppConfig.mode] == [AppMode.server].
  DatabaseHelper get dbHelper => DatabaseHelper();

  //region CRUD Operations
  /// Persists [config], replacing any existing configuration record.
  Future<Result<ServerConfig>> createConfiguration(ServerConfig config) async {
    final dbHelper = this.dbHelper;
    if (AppConfig.mode == AppMode.server) {
      final id = await dbHelper.createConfiguration(config);
      if (id >= 0) {
        return Result.success(data: config);
      } else {
        return Result.error(errorMessage: 'Error creating configuration');
      }
    } else {
      final created = await ApiService.config().createConfig(config);
      if (created != null) {
        return Result.success(data: created);
      } else {
        return Result.error(errorMessage: 'Error creating configuration via API');
      }
    }
  }

  /// Returns the stored [ServerConfig], or `null` in the result data if none
  /// has been saved yet.
  Future<Result<ServerConfig?>> readConfiguration() async {
    final dbHelper = this.dbHelper;
    try {
      ServerConfig? config;
      if (AppConfig.mode == AppMode.server) {
        config = await dbHelper.readConfiguration();
      } else {
        config = await ApiService.config().getConfig();
      }
      return Result.success(data: config);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Updates the existing [config] in the data source.
  Future<Result<ServerConfig>> updateConfiguration(ServerConfig config) async {
    final dbHelper = this.dbHelper;
    if (AppConfig.mode == AppMode.server) {
      final rows = await dbHelper.updateConfiguration(config);
      if (rows >= 0) {
        return Result.success(data: config);
      } else {
        return Result.error(errorMessage: 'Error updating configuration');
      }
    } else {
      final updated = await ApiService.config().updateConfig(config);
      if (updated != null) {
        return Result.success(data: updated);
      } else {
        return Result.error(errorMessage: 'Error updating configuration via API');
      }
    }
  }

  /// Deletes the stored configuration from the data source.
  Future<Result<void>> deleteConfiguration() async {
    final dbHelper = this.dbHelper;
    if (AppConfig.mode == AppMode.server) {
      await dbHelper.deleteConfiguration();
      return Result.success();
    } else {
      final returnValue = await ApiService.config().deleteConfig();
      if (returnValue == 'OK') {
        return Result.success();
      }
      return Result.error(errorMessage: returnValue);
    }
  }
  //endregion
}
