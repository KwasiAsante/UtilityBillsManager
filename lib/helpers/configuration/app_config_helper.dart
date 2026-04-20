import '../database/database_helper.dart';
import '../../data/models/app_configuration.dart';
import '../../data/models/result.dart';

/// Singleton service layer for app configuration persistence.
///
/// Always uses the local SQLite [DatabaseHelper] regardless of [AppMode] —
/// routing through the API would be a chicken-and-egg problem since
/// [AppConfiguration.baseWebAPI] is needed to reach the API in the first place.
class AppConfigHelper {
  static final AppConfigHelper _instance = AppConfigHelper._internal();

  factory AppConfigHelper() => _instance;

  AppConfigHelper._internal();

  DatabaseHelper get dbHelper => DatabaseHelper();

  /// Returns the stored [AppConfiguration], or `null` in the result data if
  /// none has been saved yet.
  Future<Result<AppConfiguration?>> readConfiguration() async {
    try {
      final config = await dbHelper.readAppConfiguration();
      return Result.success(data: config);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Persists [config], replacing any existing app configuration record.
  Future<Result<AppConfiguration>> saveConfiguration(
      AppConfiguration config) async {
    final id = await dbHelper.saveAppConfiguration(config);
    if (id >= 0) {
      return Result.success(data: config);
    } else {
      return Result.error(errorMessage: 'Error saving app configuration');
    }
  }
}
