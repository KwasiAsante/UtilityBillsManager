import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../utils/app_logger.dart';
import 'update_info.dart';

/// Fetches `latest.json` from the gh-pages branch and compares it with the
/// version currently running.
///
/// Results are cached for the lifetime of the process so subsequent calls
/// (e.g. navigating back to the home screen) do not generate extra network
/// requests.
///
/// Usage:
/// ```dart
/// final info = await UpdateService.instance.checkForUpdate();
/// if (info != null && info.isUpdateAvailable) { ... }
/// ```
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  /// URL of the JSON file pushed to GitHub Pages by the publish workflow.
  /// Update this if the GitHub username or repo name ever changes.
  static const _latestJsonUrl =
      'https://kwasiasante.github.io/UtilityBillsManager/latest.json';

  static const _tag = '[UpdateService]';
  static const _timeout = Duration(seconds: 10);

  UpdateInfo? _cached;

  /// Checks for an available update.
  ///
  /// Returns an [UpdateInfo] (callers should check [UpdateInfo.isUpdateAvailable]).
  /// Returns `null` when the check cannot be completed (no network, server
  /// error, malformed JSON, etc.).
  Future<UpdateInfo?> checkForUpdate() async {
    if (_cached != null) {
      AppLogger().d('$_tag Using cached result (${_cached!.latestVersion})');
      return _cached;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild   = int.tryParse(packageInfo.buildNumber) ?? 0;

      AppLogger().d('$_tag Fetching $_latestJsonUrl');
      final response = await http
          .get(Uri.parse(_latestJsonUrl))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        AppLogger().w(
          '$_tag Server returned ${response.statusCode}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(
        json,
        currentVersion: currentVersion,
        currentBuild:   currentBuild,
      );

      _cached = info;
      AppLogger().i(
        '$_tag Latest: ${info.latestVersion}+${info.latestBuild}  '
        'Current: ${info.currentVersion}+${info.currentBuild}  '
        'Update available: ${info.isUpdateAvailable}',
      );
      return info;
    } catch (e, st) {
      AppLogger().w('$_tag Check failed', error: e, stackTrace: st);
      return null;
    }
  }

  /// Clears the in-memory cache so the next call fetches fresh data.
  void invalidateCache() => _cached = null;
}
