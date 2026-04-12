/// Native implementation of [initDb] (Android, iOS, macOS, Windows, Linux).
///
/// On desktop platforms (Windows, Linux, macOS) the FFI factory is required
/// because sqflite's default implementation targets Android/iOS only.
/// [sqfliteFfiInit] loads the native SQLite dynamic library and
/// [databaseFactoryFfi] replaces the default factory.
///
/// On Android and iOS the default factory is already correct, so no changes
/// are needed.
library;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;

void initDb() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Android/iOS: sqflite works natively, nothing needed
}