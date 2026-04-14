import 'package:flutter/foundation.dart';

import '../../config/server_configuration.dart';
import '../models/result.dart';
import '../models/server_config.dart';
import '../../helpers/configuration/server_config_helper.dart';

/// Singleton [ChangeNotifier] repository that manages the in-memory server
/// configuration and delegates persistence to [ServerConfigHelper].
///
/// Unlike list-based repositories, this holds a single nullable [config] record
/// (the server stores at most one configuration at a time).
///
/// Screens subscribe via `context.watch<ServerConfigRepository>()`. Any
/// mutating operation (create / update / delete) automatically calls [reload]
/// so [config] stays current before [notifyListeners] fires.
class ServerConfigRepository extends ChangeNotifier {
  static final ServerConfigRepository _instance =
      ServerConfigRepository._internal();
  factory ServerConfigRepository() => _instance;
  ServerConfigRepository._internal();

  final ServerConfigHelper _helper = ServerConfigHelper();

  /// The current configuration held in memory, or `null` if none has been
  /// saved yet.
  ServerConfig? config;

  /// The error message from the most recent failed operation, or `null` if the
  /// last operation succeeded.
  String? lastError;

  /// Fetches the stored configuration and refreshes [config].
  ///
  /// Always calls [notifyListeners] regardless of outcome.
  Future<void> reload() async {
    final result = await _helper.readConfiguration();
    if (result.isSuccess) {
      config = result.data;
      lastError = null;
    } else {
      lastError = result.errorMessage;
    }

    ServerConfiguration.updateServerConfigPreferences();

    notifyListeners();
  }

  /// Persists [serverConfig], replacing any existing record, and reloads on
  /// success.
  Future<Result<ServerConfig>> create(ServerConfig serverConfig) async {
    final result = await _helper.createConfiguration(serverConfig);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Updates the existing [serverConfig] record and reloads on success.
  Future<Result<ServerConfig>> update(ServerConfig serverConfig) async {
    final result = await _helper.updateConfiguration(serverConfig);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Deletes the stored configuration and reloads on success.
  Future<Result<void>> delete() async {
    final result = await _helper.deleteConfiguration();
    if (result.isSuccess) await reload();
    return result;
  }
}
