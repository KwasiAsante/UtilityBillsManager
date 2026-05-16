import 'dart:io';

import 'package:flutter/foundation.dart';

/// Download URLs for every platform as published in `gh-pages/latest.json`.
class UpdateDownloads {
  final String? windowsMsix;
  final String? windowsExe;
  final String? windowsMsi;
  final String? android;
  final String? macos;
  final String? linux;

  const UpdateDownloads({
    this.windowsMsix,
    this.windowsExe,
    this.windowsMsi,
    this.android,
    this.macos,
    this.linux,
  });

  factory UpdateDownloads.fromJson(Map<String, dynamic> json) {
    return UpdateDownloads(
      windowsMsix: json['windows_msix'] as String?,
      windowsExe:  json['windows_exe']  as String?,
      windowsMsi:  json['windows_msi']  as String?,
      android:     json['android']      as String?,
      macos:       json['macos']        as String?,
      linux:       json['linux']        as String?,
    );
  }

  /// The primary download URL for the running platform.
  /// Returns `null` on web (browser handles updates independently).
  String? get forPlatform {
    if (kIsWeb) return null;
    if (Platform.isWindows) return windowsExe;   // EXE is the friendliest default
    if (Platform.isAndroid) return android;
    if (Platform.isMacOS)   return macos;
    if (Platform.isLinux)   return linux;
    return null;
  }

  /// Whether the current platform has any download URL.
  bool get hasPlatformDownload => forPlatform != null;
}

/// Parsed representation of `gh-pages/latest.json`, enriched with the app's
/// currently running version so callers can determine whether an update is
/// available without any extra work.
class UpdateInfo {
  /// The latest published version string, e.g. `"1.3.0"`.
  final String latestVersion;

  /// The latest published build number, e.g. `7`.
  final int latestBuild;

  /// The GitHub release tag, e.g. `"v1.3.0"`.
  final String tag;

  /// Download URLs per platform.
  final UpdateDownloads downloads;

  /// The version string currently running, from [PackageInfo].
  final String currentVersion;

  /// The build number currently running, from [PackageInfo].
  final int currentBuild;

  const UpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.tag,
    required this.downloads,
    required this.currentVersion,
    required this.currentBuild,
  });

  factory UpdateInfo.fromJson(
    Map<String, dynamic> json, {
    required String currentVersion,
    required int currentBuild,
  }) {
    return UpdateInfo(
      latestVersion: json['version']  as String? ?? '0.0.0',
      latestBuild:   json['build']    as int?    ?? 0,
      tag:           json['tag']      as String? ?? '',
      downloads:     UpdateDownloads.fromJson(
        (json['downloads'] as Map<String, dynamic>?) ?? {},
      ),
      currentVersion: currentVersion,
      currentBuild:   currentBuild,
    );
  }

  /// `true` when the latest published version is strictly newer than the one
  /// currently running.  Compares major.minor.patch first; falls back to the
  /// build number when all three components are equal.
  bool get isUpdateAvailable {
    final latest  = _parseSemver(latestVersion);
    final current = _parseSemver(currentVersion);

    for (var i = 0; i < 3; i++) {
      if (latest[i] > current[i]) return true;
      if (latest[i] < current[i]) return false;
    }
    return latestBuild > currentBuild;
  }

  static List<int> _parseSemver(String v) {
    final parts = v.split('.');
    return List.generate(3, (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }
}
