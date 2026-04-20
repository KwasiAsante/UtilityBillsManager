# App Configuration Model and Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `SharedPreferences`-backed `apiBaseUrl` storage with a SQLite-backed `AppConfiguration` model so the value persists reliably on all platforms including web.

**Architecture:** A new `AppConfiguration` model and `AppConfigHelper` follow the exact same pattern as `ServerConfig`/`ServerConfigHelper`. `DatabaseHelper` gains an `app_configuration` table (schema version 16). `AppConfig.load()` reads from SQLite into an in-memory cache at startup; `apiBaseUrl` reads the cache first, then falls back to SharedPreferences → dart-define → default.

**Tech Stack:** Flutter, Dart, `sqflite` / `sqflite_common_ffi_web`, `uuid`

---

## File Map

| File | Action |
|---|---|
| `lib/data/models/app_configuration.dart` | Create — model with `id`, `configId`, `baseWebAPI` |
| `lib/helpers/configuration/app_config_helper.dart` | Create — always-local SQLite CRUD singleton |
| `lib/helpers/database/database_helper.dart` | Modify — bump version to 16, add table + CRUD methods |
| `lib/config/app_config.dart` | Modify — add `_appConfig` cache, `load()`, update `apiBaseUrl` + `setApiBaseUrl` |
| `lib/main.dart` | Modify — add `await AppConfig.load()` after DB open |
| `test/data/models/app_configuration_test.dart` | Create — unit tests for serialization |

---

### Task 1: Create the feature branch

- [ ] **Step 1: Create and check out the branch**

```bash
git checkout -b feat/app-configuration
```

- [ ] **Step 2: Verify**

```bash
git branch --show-current
```
Expected: `feat/app-configuration`

---

### Task 2: `AppConfiguration` model (TDD)

**Files:**
- Create: `test/data/models/app_configuration_test.dart`
- Create: `lib/data/models/app_configuration.dart`

- [ ] **Step 1: Create the test file**

Write `test/data/models/app_configuration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/app_configuration.dart';

void main() {
  group('AppConfiguration', () {
    test('toJson omits id and includes configId and baseWebAPI', () {
      final config = AppConfiguration(
        id: 1,
        configId: 'test-uuid',
        baseWebAPI: 'http://example.com',
      );
      final json = config.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['configId'], equals('test-uuid'));
      expect(json['baseWebAPI'], equals('http://example.com'));
    });

    test('fromJson round-trips a full config', () {
      final map = {
        'id': 1,
        'configId': 'test-uuid',
        'baseWebAPI': 'http://example.com',
      };
      final config = AppConfiguration.fromJson(map);
      expect(config.id, equals(1));
      expect(config.configId, equals('test-uuid'));
      expect(config.baseWebAPI, equals('http://example.com'));
    });

    test('fromJson with all null fields', () {
      final config = AppConfiguration.fromJson({
        'id': null,
        'configId': null,
        'baseWebAPI': null,
      });
      expect(config.id, isNull);
      expect(config.configId, isNull);
      expect(config.baseWebAPI, isNull);
    });

    test('fromJson with missing keys returns nulls', () {
      final config = AppConfiguration.fromJson({});
      expect(config.id, isNull);
      expect(config.configId, isNull);
      expect(config.baseWebAPI, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
flutter test test/data/models/app_configuration_test.dart
```
Expected: FAIL — `app_configuration.dart` does not exist.

- [ ] **Step 3: Create `lib/data/models/app_configuration.dart`**

```dart
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
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
flutter test test/data/models/app_configuration_test.dart
```
Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/app_configuration.dart \
        test/data/models/app_configuration_test.dart
git commit -m "feat: add AppConfiguration model with toJson/fromJson"
```

---

### Task 3: Update `DatabaseHelper`

**Files:**
- Modify: `lib/helpers/database/database_helper.dart`

- [ ] **Step 1: Read the file**

Read `lib/helpers/database/database_helper.dart` in full before editing.

- [ ] **Step 2: Add import for `AppConfiguration`**

Find:
```dart
import '../../data/models/server_config.dart';
```

Replace with:
```dart
import '../../data/models/app_configuration.dart';
import '../../data/models/server_config.dart';
```

- [ ] **Step 3: Bump `_databaseVersion` from 15 to 16**

Find:
```dart
  static const _databaseVersion = 15;
```

Replace with:
```dart
  static const _databaseVersion = 16;
```

- [ ] **Step 4: Add `app_configuration` table to `_onCreate`**

Find the closing of the `_onCreate` method — the last `await db.execute` block inside it:

```dart
    await db.execute('''
      CREATE TABLE configuration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        configId TEXT NOT NULL,
        emailAddress TEXT,
        emailPassword TEXT,
        emailImapServer TEXT,
        emailImapPort INTEGER,
        emailImapSecure INTEGER,
        emailEarliestDate TEXT,
        emailSyncDelayDuration INTEGER,
        emailSyncInterval INTEGER
      )
    ''');
  }
```

Replace with:
```dart
    await db.execute('''
      CREATE TABLE configuration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        configId TEXT NOT NULL,
        emailAddress TEXT,
        emailPassword TEXT,
        emailImapServer TEXT,
        emailImapPort INTEGER,
        emailImapSecure INTEGER,
        emailEarliestDate TEXT,
        emailSyncDelayDuration INTEGER,
        emailSyncInterval INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE app_configuration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        configId TEXT,
        baseWebAPI TEXT
      )
    ''');
  }
```

- [ ] **Step 5: Add migration block for version 16 in `_onUpgrade`**

Find:
```dart
    if (oldVersion < 15) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS configuration (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          configId TEXT NOT NULL,
          emailAddress TEXT,
          emailPassword TEXT,
          emailImapServer TEXT,
          emailImapPort INTEGER,
          emailImapSecure INTEGER,
          emailEarliestDate TEXT,
          emailSyncDelayDuration INTEGER,
          emailSyncInterval INTEGER
        )
      ''');
    }
  }
```

Replace with:
```dart
    if (oldVersion < 15) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS configuration (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          configId TEXT NOT NULL,
          emailAddress TEXT,
          emailPassword TEXT,
          emailImapServer TEXT,
          emailImapPort INTEGER,
          emailImapSecure INTEGER,
          emailEarliestDate TEXT,
          emailSyncDelayDuration INTEGER,
          emailSyncInterval INTEGER
        )
      ''');
    }

    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_configuration (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          configId TEXT,
          baseWebAPI TEXT
        )
      ''');
    }
  }
```

- [ ] **Step 6: Add `app_configuration` CRUD methods**

Find:
```dart
  //region Configuration
  /// Inserts [config] into the `configuration` table, replacing any existing
```

Insert the following block immediately before that line:

```dart
  //region App Configuration
  /// Clears the `app_configuration` table and inserts [config] as the single
  /// row. Returns the new row id.
  Future<int> saveAppConfiguration(AppConfiguration config) async {
    final db = await database;
    await db.delete('app_configuration');
    return await db.insert('app_configuration', config.toJson());
  }

  /// Returns the stored [AppConfiguration], or `null` if none exists.
  Future<AppConfiguration?> readAppConfiguration() async {
    final db = await database;
    final result = await db.query('app_configuration', limit: 1);
    if (result.isEmpty) return null;
    return AppConfiguration.fromJson(result.first);
  }

  /// Deletes all rows from `app_configuration`. Returns deleted row count.
  Future<int> deleteAppConfiguration() async {
    final db = await database;
    return await db.delete('app_configuration');
  }
  //endregion

```

- [ ] **Step 7: Verify**

```bash
flutter analyze lib/helpers/database/database_helper.dart
```
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/helpers/database/database_helper.dart
git commit -m "feat: add app_configuration table and CRUD to DatabaseHelper (schema v16)"
```

---

### Task 4: Create `AppConfigHelper`

**Files:**
- Create: `lib/helpers/configuration/app_config_helper.dart`

- [ ] **Step 1: Create the file**

Write `lib/helpers/configuration/app_config_helper.dart`:

```dart
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
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/helpers/configuration/app_config_helper.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/helpers/configuration/app_config_helper.dart
git commit -m "feat: add AppConfigHelper singleton for SQLite-backed app configuration"
```

---

### Task 5: Update `AppConfig`

**Files:**
- Modify: `lib/config/app_config.dart`

- [ ] **Step 1: Read the file**

Read `lib/config/app_config.dart` in full before editing.

- [ ] **Step 2: Add imports**

Find:
```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../utils/preferences.dart';
```

Replace with:
```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/models/app_configuration.dart';
import '../helpers/configuration/app_config_helper.dart';
import '../utils/preferences.dart';
```

- [ ] **Step 3: Add the `_appConfig` cache and `load()` method**

Find:
```dart
class AppConfig {
  /// Loads optional local secrets from a bundled asset and pre-warms
  /// the SharedPreferences instance.
  ///
  /// Call this once during startup (before reading any config).
  static Future<void> init() async {
    await Future.wait([Preferences.sharedPrefs]);
  }
```

Replace with:
```dart
class AppConfig {
  /// In-memory cache populated by [load]. All synchronous getters read from
  /// this cache after startup so the DB is never hit on the hot path.
  static AppConfiguration? _appConfig;

  /// Loads optional local secrets from a bundled asset and pre-warms
  /// the SharedPreferences instance.
  ///
  /// Call this once during startup (before reading any config).
  static Future<void> init() async {
    await Future.wait([Preferences.sharedPrefs]);
  }

  /// Reads [AppConfiguration] from SQLite into [_appConfig].
  ///
  /// Must be called after the database is open and before [apiBaseUrl] is
  /// first read. In `main.dart` this runs immediately after
  /// `await DatabaseHelper().database`.
  static Future<void> load() async {
    final result = await AppConfigHelper().readConfiguration();
    if (result.isSuccess) {
      _appConfig = result.data;
    }
  }
```

- [ ] **Step 4: Update `apiBaseUrl` getter**

Find:
```dart
  /// Base URL used by the app when it needs to call the API.
  ///
  /// - Server mode: defaults to localhost (self-hosted API)
  /// - Client mode: defaults to `API_BASE_URL` (connect to another host)
  static String get apiBaseUrl {
    if (mode == AppMode.server) {
      return 'http://127.0.0.1:8080';
    }

    String? apiUrl = Preferences.getString('API_BASE_URL');

    if (apiUrl != null && apiUrl.isNotEmpty) {
      if (apiUrl == 'http://192.168.2.172:8080' &&
          (defaultTargetPlatform != TargetPlatform.android ||
              defaultTargetPlatform != TargetPlatform.iOS)) {
        apiUrl = 'http://127.0.0.1:8080';
      }
      return apiUrl;
    }

    apiUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _defaultApiBaseUrl,
    );

    if (apiUrl == 'http://192.168.2.172:8080' &&
        (defaultTargetPlatform != TargetPlatform.android ||
        defaultTargetPlatform != TargetPlatform.iOS)) {
      apiUrl = 'http://127.0.0.1:8080';
    }

    return apiUrl;
  }
```

Replace with:
```dart
  /// Base URL used by the app when it needs to call the API.
  ///
  /// Resolution order (highest priority first):
  /// 1. [_appConfig.baseWebAPI] — SQLite-backed, reliable across sessions
  /// 2. SharedPreferences `API_BASE_URL` — legacy fallback
  /// 3. `dart-define` `API_BASE_URL`
  /// 4. Hardcoded default ([_defaultApiBaseUrl])
  ///
  /// - Server mode always returns localhost regardless of stored value.
  static String get apiBaseUrl {
    if (mode == AppMode.server) {
      return 'http://127.0.0.1:8080';
    }

    // 1. SQLite-backed cache (survives browser/app restarts on all platforms)
    if (_appConfig?.baseWebAPI != null &&
        _appConfig!.baseWebAPI!.isNotEmpty) {
      return _appConfig!.baseWebAPI!;
    }

    // 2. SharedPreferences fallback (legacy)
    String? apiUrl = Preferences.getString('API_BASE_URL');

    if (apiUrl != null && apiUrl.isNotEmpty) {
      if (apiUrl == 'http://192.168.2.172:8080' &&
          (defaultTargetPlatform != TargetPlatform.android ||
              defaultTargetPlatform != TargetPlatform.iOS)) {
        apiUrl = 'http://127.0.0.1:8080';
      }
      return apiUrl;
    }

    // 3. dart-define / hardcoded default
    apiUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _defaultApiBaseUrl,
    );

    if (apiUrl == 'http://192.168.2.172:8080' &&
        (defaultTargetPlatform != TargetPlatform.android ||
        defaultTargetPlatform != TargetPlatform.iOS)) {
      apiUrl = 'http://127.0.0.1:8080';
    }

    return apiUrl;
  }
```

- [ ] **Step 5: Update `setApiBaseUrl`**

Find:
```dart
  static Future<void> setApiBaseUrl(String newUrl) async {
    await Preferences.setString('API_BASE_URL', newUrl);
  }
```

Replace with:
```dart
  static Future<void> setApiBaseUrl(String newUrl) async {
    final config = AppConfiguration(
      configId: _appConfig?.configId ?? const Uuid().v4(),
      baseWebAPI: newUrl,
    );
    await AppConfigHelper().saveConfiguration(config);
    _appConfig = config;
    // Keep SharedPreferences in sync for any legacy consumers.
    await Preferences.setString('API_BASE_URL', newUrl);
  }
```

- [ ] **Step 6: Verify**

```bash
flutter analyze lib/config/app_config.dart
```
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/config/app_config.dart
git commit -m "feat: add AppConfig.load() and update apiBaseUrl to read from SQLite cache"
```

---

### Task 6: Update `main.dart`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Read the file**

Read `lib/main.dart` in full before editing.

- [ ] **Step 2: Add `await AppConfig.load()` after DB open**

Find:
```dart
  await DatabaseHelper().database;

  ApiService.configure(baseUrl: AppConfig.apiBaseUrl);
```

Replace with:
```dart
  await DatabaseHelper().database;

  await AppConfig.load();

  ApiService.configure(baseUrl: AppConfig.apiBaseUrl);
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/main.dart
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: call AppConfig.load() at startup after database is open"
```

---

### Task 7: Full test suite and PR

- [ ] **Step 1: Run the full test suite**

```bash
flutter test
```
Expected: All tests pass (no regressions).

- [ ] **Step 2: Push the branch**

```bash
git push -u origin feat/app-configuration
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create \
  --title "feat: persist AppConfiguration (baseWebAPI) in SQLite" \
  --body "$(cat <<'EOF'
## Summary
- Adds `AppConfiguration` model (`id`, `configId`, `baseWebAPI`) with `toJson`/`fromJson`
- Adds `AppConfigHelper` singleton — always writes to local SQLite (no API routing, avoids chicken-and-egg with baseWebAPI)
- Bumps DB schema to version 16, adds `app_configuration` table with migration
- `AppConfig.load()` reads SQLite into `_appConfig` cache at startup (called after `await DatabaseHelper().database`)
- `apiBaseUrl` getter now checks `_appConfig.baseWebAPI` first, then falls back to SharedPreferences → dart-define → default
- `setApiBaseUrl` writes to both SQLite and SharedPreferences (legacy compat)
- Fixes unreliable persistence of API base URL on web (localStorage → IndexedDB via sqflite_common_ffi_web)

## Test plan
- [ ] Run `flutter test` — all tests pass
- [ ] Open the app, set a custom API Base URL in App Configuration settings, close/reopen — URL is restored
- [ ] On web: set URL, clear localStorage in DevTools, reload — URL is still restored (IndexedDB intact)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
