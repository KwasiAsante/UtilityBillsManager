import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web implementation of [initDb].
///
/// Replaces the default sqflite factory with [databaseFactoryFfiWeb], which
/// persists the SQLite database in the browser's IndexedDB so data survives
/// page refreshes.  Must be called before the first [DatabaseHelper] access.
void initDb() {
  databaseFactory = databaseFactoryFfiWeb;
}