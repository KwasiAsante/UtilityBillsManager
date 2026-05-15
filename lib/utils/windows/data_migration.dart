import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_logger.dart';

/// One-time migration that moves app data written by path_provider from the
/// old Windows paths (CompanyName = "com.example") to the new paths
/// (CompanyName = "AsanteDevs", ProductName = "Utility Bills Manager").
///
/// Background
/// ----------
/// path_provider on Windows derives its directories from the CompanyName and
/// ProductName fields in the executable's VERSIONINFO resource (Runner.rc).
/// When those strings changed, the directories changed:
///
///   Old APPDATA path:   %APPDATA%\com.example\utility_bills_manager
///   New APPDATA path:   %APPDATA%\AsanteDevs\Utility Bills Manager
///
///   Old LOCALAPPDATA path:   %LOCALAPPDATA%\com.example\utility_bills_manager
///   New LOCALAPPDATA path:   %LOCALAPPDATA%\AsanteDevs\Utility Bills Manager
///
/// The migration copies every file from the old directories to the new ones,
/// then removes the old directories.  It is a no-op once the old directories
/// are gone, so it is safe to call on every startup.
///
/// Call [DataMigration.runIfNeeded] as early as possible in [main] —
/// before the database is opened — so all services see the new path.
class DataMigration {
  static const _tag = '[DataMigration]';

  DataMigration._();

  /// Entry point.  Does nothing on non-Windows platforms.
  static Future<void> runIfNeeded() async {
    if (!Platform.isWindows) return;

    final appData = Platform.environment['APPDATA'];
    final localAppData = Platform.environment['LOCALAPPDATA'];

    if (appData != null) {
      await _migrate(
        from: p.join(appData, 'com.example', 'utility_bills_manager'),
        to: p.join(appData, 'AsanteDevs', 'Utility Bills Manager'),
      );
    }

    if (localAppData != null) {
      await _migrate(
        from: p.join(localAppData, 'com.example', 'utility_bills_manager'),
        to: p.join(localAppData, 'AsanteDevs', 'Utility Bills Manager'),
      );
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static Future<void> _migrate({
    required String from,
    required String to,
  }) async {
    final fromDir = Directory(from);
    if (!fromDir.existsSync()) return; // nothing to migrate

    AppLogger().i('$_tag Migrating $from → $to');

    try {
      final toDir = Directory(to);
      if (!toDir.existsSync()) toDir.createSync(recursive: true);

      await _copyDir(fromDir, toDir);
      await fromDir.delete(recursive: true);

      // Remove the now-empty parent (com.example) if it has no siblings.
      final parent = Directory(p.dirname(from));
      if (parent.existsSync() && parent.listSync().isEmpty) {
        await parent.delete();
      }

      AppLogger().i('$_tag Migration complete');
    } catch (e, st) {
      // Non-fatal: the app can still run; old data simply stays at the old path.
      AppLogger().w('$_tag Migration failed — old data kept at $from', error: e, stackTrace: st);
    }
  }

  static Future<void> _copyDir(Directory src, Directory dst) async {
    await for (final entity in src.list()) {
      final name = p.basename(entity.path);
      final destPath = p.join(dst.path, name);

      if (entity is Directory) {
        final subDst = Directory(destPath);
        if (!subDst.existsSync()) subDst.createSync();
        await _copyDir(entity, subDst);
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }
}
