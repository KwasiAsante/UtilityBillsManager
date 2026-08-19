import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/app_logger.dart';

/// Reads and shares the on-device log files written by [AppLogger], so they
/// can be inspected without a USB debugger.
class LogFileService {
  /// Returns log files sorted newest-first by modification time.
  ///
  /// Returns an empty list on web, or if the logs directory doesn't exist yet
  /// (e.g. nothing has been logged since the app was installed).
  static Future<List<File>> listLogFiles() async {
    if (kIsWeb) return [];

    final dir = await AppLogger.logsDirectory();
    if (!await dir.exists()) return [];

    final entities = await dir.list().toList();
    final files =
        entities
            .whereType<File>()
            .where((f) => f.path.endsWith('.log'))
            .toList();

    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  static Future<void> shareFile(File file) {
    return SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  static Future<void> shareAll(List<File> files) {
    if (files.isEmpty) return Future.value();
    return SharePlus.instance.share(
      ShareParams(files: files.map((f) => XFile(f.path)).toList()),
    );
  }
}
