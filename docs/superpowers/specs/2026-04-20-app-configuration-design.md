# Design: App Configuration Model and Persistence

**Date:** 2026-04-20
**Status:** Approved

---

## Problem

`AppConfig.apiBaseUrl` is currently persisted via `SharedPreferences`, which on web uses `localStorage`. This means the value can be lost when the browser clears site data, making the app unreachable after a session ends. The fix is to store app configuration in SQLite (via `sqflite_common_ffi_web` on web, native `sqflite` on other platforms), which uses IndexedDB on web and is only removed when the app itself is uninstalled.

---

## Scope

**Created:** 2 files — `AppConfiguration` model, `AppConfigHelper`

**Modified:** 3 files — `DatabaseHelper`, `AppConfig`, `main.dart`

**Unchanged:** `AppConfigScreen` (already calls `AppConfig.setApiBaseUrl()`)

| File | Change |
|---|---|
| `lib/data/models/app_configuration.dart` | New model with `id`, `configId`, `baseWebAPI` |
| `lib/helpers/configuration/app_config_helper.dart` | New singleton helper — always-local SQLite CRUD |
| `lib/helpers/database/database_helper.dart` | Add `app_configuration` table + `readAppConfiguration` / `saveAppConfiguration` methods |
| `lib/config/app_config.dart` | Add `_appConfig` cache + `load()` + update `apiBaseUrl` getter + update `setApiBaseUrl` |
| `lib/main.dart` | Call `await AppConfig.load()` after DB open, before `ApiService.configure()` |

---

## Data Model

```dart
class AppConfiguration {
  final int? id;
  final String? configId;
  String? baseWebAPI;

  AppConfiguration({this.id, this.configId, this.baseWebAPI});

  Map<String, dynamic> toJson() => {
    'configId': configId,
    'baseWebAPI': baseWebAPI,
  };

  factory AppConfiguration.fromJson(Map<String, dynamic> map) =>
      AppConfiguration(
        id: map['id'] as int?,
        configId: map['configId'] as String?,
        baseWebAPI: map['baseWebAPI'] as String?,
      );
}
```

SQLite table (added to `DatabaseHelper`):

```sql
CREATE TABLE app_configuration (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  configId TEXT,
  baseWebAPI TEXT
)
```

Single-row semantics: `saveAppConfiguration` clears the table then inserts, same as `createConfiguration` does for `ServerConfig`.

---

## AppConfigHelper

Always uses local SQLite regardless of `AppMode` — routing through the API would be a chicken-and-egg problem since `baseWebAPI` is needed to reach the API.

```dart
class AppConfigHelper {
  // singleton

  Future<Result<AppConfiguration?>> readConfiguration() async { ... }

  /// Clears the table and inserts [config] as the single row.
  Future<Result<AppConfiguration>> saveConfiguration(AppConfiguration config) async { ... }
}
```

---

## AppConfig Changes

```dart
static AppConfiguration? _appConfig;

/// Loads AppConfiguration from SQLite into the in-memory cache.
/// Call after the database is open, before ApiService.configure().
static Future<void> load() async {
  final result = await AppConfigHelper().readConfiguration();
  if (result.isSuccess) {
    _appConfig = result.data;
  }
}
```

Updated `apiBaseUrl` getter priority:
1. `_appConfig?.baseWebAPI` — SQLite-backed, reliable on all platforms
2. SharedPreferences `API_BASE_URL` — legacy fallback
3. `dart-define` `API_BASE_URL`
4. Hardcoded default (`https://kwasi-utilitybills.duckdns.org`)

Updated `setApiBaseUrl`:

```dart
static Future<void> setApiBaseUrl(String url) async {
  final config = AppConfiguration(
    configId: _appConfig?.configId ?? const Uuid().v4(),
    baseWebAPI: url,
  );
  await AppConfigHelper().saveConfiguration(config);
  _appConfig = config;
}
```

---

## main.dart Change

One line added after the database is open, before `ApiService.configure()`:

```dart
await DatabaseHelper().database;
await AppConfig.load();           // NEW
ApiService.configure(baseUrl: AppConfig.apiBaseUrl);
```

---

## First-Run Behaviour

On first run the `app_configuration` table is empty. `AppConfig.load()` sets `_appConfig` to `null`, and `apiBaseUrl` falls through to SharedPreferences → dart-define → default. Once the user saves a URL via `AppConfigScreen`, it is written to SQLite and will survive all subsequent sessions.

No automatic migration from SharedPreferences — the user saves once and the value is persisted durably from that point forward.

---

## Testing

Unit tests for `AppConfiguration` serialization:
- `toJson` produces the expected map
- `fromJson` round-trips correctly (including `null` fields)
- `fromJson` with a full map sets all fields

No widget tests needed — `AppConfigScreen` is unchanged.
