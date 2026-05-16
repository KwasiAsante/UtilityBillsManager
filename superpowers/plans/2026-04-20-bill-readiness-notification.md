# Bill Readiness Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After every new-bill SSE notification, check whether all expected bills for each configured rentor have arrived; if so, send a local "compose bill summary" notification that navigates directly to `MessagePreviewScreen` when tapped.

**Architecture:** A new `BillNotificationTrackerHelper` persists per-(rentor, bill) receipt records in SQLite. `BillReadinessService` contains the pure readiness-check logic and is injected with the helper for testability. `NativeNotificationService.handleSseEvent` calls the service after each bill reload and shows compose notifications; tap routing is handled via a `GlobalKey<NavigatorState>` registered in `main.dart`.

**Tech Stack:** Flutter, Dart, `sqflite`, `flutter_local_notifications`, existing `BillSummaryService`, `BillsRepository`, `RentorsRepository`

---

## File Map

| File | Action |
|---|---|
| `lib/data/models/bill_notification_tracker.dart` | Create — model with toJson/fromJson |
| `lib/helpers/bill_readiness/bill_notification_tracker_helper.dart` | Create — SQLite CRUD singleton |
| `lib/services/bill_readiness/bill_readiness_service.dart` | Create — readiness logic + `ComposeNotification` |
| `lib/services/notification/notification_service.dart` | Modify — add `setNavigatorKey` and `handleLaunchNotification` to interface |
| `lib/services/notification/notification_service_native.dart` | Modify — wire readiness check, add compose notification display, tap handler |
| `lib/services/notification/notification_service_web.dart` | Modify — add no-op `setNavigatorKey` and `handleLaunchNotification` |
| `lib/helpers/database/database_helper.dart` | Modify — schema v17, two new tables, four CRUD methods |
| `lib/main.dart` | Modify — register navigator key, call `handleLaunchNotification` |
| `test/services/bill_readiness/bill_readiness_service_test.dart` | Create — unit tests |

---

### Task 1: `BillNotificationTracker` model

**Files:**
- Create: `lib/data/models/bill_notification_tracker.dart`
- Create: `test/data/models/bill_notification_tracker_test.dart`

- [ ] **Step 1: Write the failing tests**

Write `test/data/models/bill_notification_tracker_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill_notification_tracker.dart';

void main() {
  group('BillNotificationTracker', () {
    test('toJson omits id', () {
      final t = BillNotificationTracker(
        id: 1,
        rentorId: 'r1',
        billId: 'b1',
        billType: 'electric',
        month: 4,
        year: 2026,
        receivedAt: '2026-04-01T10:00:00.000',
      );
      final json = t.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['rentorId'], equals('r1'));
      expect(json['billId'], equals('b1'));
      expect(json['billType'], equals('electric'));
      expect(json['month'], equals(4));
      expect(json['year'], equals(2026));
      expect(json['receivedAt'], equals('2026-04-01T10:00:00.000'));
    });

    test('fromJson round-trips', () {
      final map = {
        'id': 5,
        'rentorId': 'r1',
        'billId': 'b2',
        'billType': 'gas',
        'month': 4,
        'year': 2026,
        'receivedAt': '2026-04-02T08:00:00.000',
      };
      final t = BillNotificationTracker.fromJson(map);
      expect(t.id, equals(5));
      expect(t.rentorId, equals('r1'));
      expect(t.billId, equals('b2'));
      expect(t.billType, equals('gas'));
      expect(t.month, equals(4));
      expect(t.year, equals(2026));
      expect(t.receivedAt, equals('2026-04-02T08:00:00.000'));
    });
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
flutter test test/data/models/bill_notification_tracker_test.dart
```
Expected: FAIL — file does not exist.

- [ ] **Step 3: Create the model**

Write `lib/data/models/bill_notification_tracker.dart`:

```dart
/// A record tracking that a specific bill notification has been received for
/// a specific rentor. Persisted in the `bill_notification_tracker` SQLite table.
class BillNotificationTracker {
  final int? id;
  final String rentorId;
  final String billId;
  final String billType;
  final int month;
  final int year;
  final String receivedAt; // ISO-8601 string

  const BillNotificationTracker({
    this.id,
    required this.rentorId,
    required this.billId,
    required this.billType,
    required this.month,
    required this.year,
    required this.receivedAt,
  });

  /// Serialises for SQLite insertion. Does NOT include [id].
  Map<String, dynamic> toJson() => {
        'rentorId': rentorId,
        'billId': billId,
        'billType': billType,
        'month': month,
        'year': year,
        'receivedAt': receivedAt,
      };

  factory BillNotificationTracker.fromJson(Map<String, dynamic> map) =>
      BillNotificationTracker(
        id: map['id'] as int?,
        rentorId: map['rentorId'] as String,
        billId: map['billId'] as String,
        billType: map['billType'] as String,
        month: map['month'] as int,
        year: map['year'] as int,
        receivedAt: map['receivedAt'] as String,
      );
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
flutter test test/data/models/bill_notification_tracker_test.dart
```
Expected: All 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/bill_notification_tracker.dart \
        test/data/models/bill_notification_tracker_test.dart
git commit -m "feat: add BillNotificationTracker model"
```

---

### Task 2: Update `DatabaseHelper` — schema v17

**Files:**
- Modify: `lib/helpers/database/database_helper.dart`

**Context:** The current schema is version 16. `PRAGMA foreign_keys = ON` is already set in `onConfigure`. The pattern for CRUD methods follows the `app_configuration` region (around line 580–620 in the current file).

- [ ] **Step 1: Read the file**

Read `lib/helpers/database/database_helper.dart` in full before making any edits.

- [ ] **Step 2: Add import for `BillNotificationTracker`**

Find:
```dart
import '../../data/models/app_configuration.dart';
import '../../data/models/server_config.dart';
```

Replace with:
```dart
import '../../data/models/app_configuration.dart';
import '../../data/models/bill_notification_tracker.dart';
import '../../data/models/server_config.dart';
```

- [ ] **Step 3: Bump `_databaseVersion` to 17**

Find:
```dart
  static const _databaseVersion = 16;
```

Replace with:
```dart
  static const _databaseVersion = 17;
```

- [ ] **Step 4: Add two tables to `_onCreate`**

Find the closing of `_onCreate` — the end of the `app_configuration` table block:

```dart
    await db.execute('''
      CREATE TABLE app_configuration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        configId TEXT,
        baseWebAPI TEXT
      )
    ''');
  }
```

Replace with:

```dart
    await db.execute('''
      CREATE TABLE app_configuration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        configId TEXT,
        baseWebAPI TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE bill_notification_tracker (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        rentorId   TEXT NOT NULL REFERENCES rentors(rentorId) ON DELETE CASCADE,
        billId     TEXT NOT NULL REFERENCES bills(billId)     ON DELETE CASCADE,
        billType   TEXT NOT NULL,
        month      INTEGER NOT NULL,
        year       INTEGER NOT NULL,
        receivedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE bill_compose_notification_log (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        rentorId  TEXT NOT NULL REFERENCES rentors(rentorId) ON DELETE CASCADE,
        month     INTEGER NOT NULL,
        year      INTEGER NOT NULL,
        billGroup TEXT NOT NULL,
        sentAt    TEXT NOT NULL
      )
    ''');
  }
```

- [ ] **Step 5: Add migration block for v17 in `_onUpgrade`**

Find:
```dart
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

Replace with:

```dart
    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_configuration (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          configId TEXT,
          baseWebAPI TEXT
        )
      ''');
    }

    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bill_notification_tracker (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          rentorId   TEXT NOT NULL REFERENCES rentors(rentorId) ON DELETE CASCADE,
          billId     TEXT NOT NULL REFERENCES bills(billId)     ON DELETE CASCADE,
          billType   TEXT NOT NULL,
          month      INTEGER NOT NULL,
          year       INTEGER NOT NULL,
          receivedAt TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS bill_compose_notification_log (
          id        INTEGER PRIMARY KEY AUTOINCREMENT,
          rentorId  TEXT NOT NULL REFERENCES rentors(rentorId) ON DELETE CASCADE,
          month     INTEGER NOT NULL,
          year      INTEGER NOT NULL,
          billGroup TEXT NOT NULL,
          sentAt    TEXT NOT NULL
        )
      ''');
    }
  }
```

- [ ] **Step 6: Add CRUD methods — find the `//region App Configuration` block**

Find:
```dart
  //region App Configuration
```

Insert the following block immediately **before** that line:

```dart
  //region Bill Notification Tracker
  /// Inserts a [BillNotificationTracker] row. Returns the new row id.
  Future<int> insertBillNotificationTracker(
      BillNotificationTracker tracker) async {
    final db = await database;
    return await db.insert('bill_notification_tracker', tracker.toJson());
  }

  /// Returns all tracker rows for [rentorId] in the given [month]/[year].
  Future<List<BillNotificationTracker>> getBillNotificationTrackers({
    required String rentorId,
    required int month,
    required int year,
  }) async {
    final db = await database;
    final rows = await db.query(
      'bill_notification_tracker',
      where: 'rentorId = ? AND month = ? AND year = ?',
      whereArgs: [rentorId, month, year],
    );
    return rows.map(BillNotificationTracker.fromJson).toList();
  }

  /// Returns `true` if a tracker row already exists for [rentorId] + [billId].
  Future<bool> billNotificationTrackerExists({
    required String rentorId,
    required String billId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'bill_notification_tracker',
      columns: ['id'],
      where: 'rentorId = ? AND billId = ?',
      whereArgs: [rentorId, billId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Inserts a compose-notification log row. Returns the new row id.
  Future<int> insertComposeNotificationLog({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async {
    final db = await database;
    return await db.insert('bill_compose_notification_log', {
      'rentorId': rentorId,
      'month': month,
      'year': year,
      'billGroup': billGroup,
      'sentAt': DateTime.now().toIso8601String(),
    });
  }

  /// Returns `true` if a log row exists for [rentorId]/[month]/[year]/[billGroup].
  Future<bool> hasComposeNotificationLog({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async {
    final db = await database;
    final rows = await db.query(
      'bill_compose_notification_log',
      columns: ['id'],
      where: 'rentorId = ? AND month = ? AND year = ? AND billGroup = ?',
      whereArgs: [rentorId, month, year, billGroup],
      limit: 1,
    );
    return rows.isNotEmpty;
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
git commit -m "feat: add bill_notification_tracker and bill_compose_notification_log tables (schema v17)"
```

---

### Task 3: `BillNotificationTrackerHelper`

**Files:**
- Create: `lib/helpers/bill_readiness/bill_notification_tracker_helper.dart`

**Context:** Follows the exact same singleton pattern as `lib/helpers/configuration/app_config_helper.dart`.

- [ ] **Step 1: Create the file**

Write `lib/helpers/bill_readiness/bill_notification_tracker_helper.dart`:

```dart
import '../database/database_helper.dart';
import '../../data/models/bill_notification_tracker.dart';

/// Singleton service layer for bill notification tracking persistence.
///
/// Wraps the two [DatabaseHelper] CRUD regions for
/// `bill_notification_tracker` and `bill_compose_notification_log`.
///
/// Declare a subclass in tests to inject fake behaviour without hitting SQLite:
///
/// ```dart
/// class FakeTrackerHelper extends BillNotificationTrackerHelper {
///   FakeTrackerHelper() : super.internal();
///   // override methods as needed
/// }
/// ```
class BillNotificationTrackerHelper {
  static final BillNotificationTrackerHelper _instance =
      BillNotificationTrackerHelper._internal();

  factory BillNotificationTrackerHelper() => _instance;

  BillNotificationTrackerHelper._internal();

  /// Exposed for subclassing in tests only.
  BillNotificationTrackerHelper.internal();

  DatabaseHelper get _db => DatabaseHelper();

  /// Returns `true` if this [billId] has already been recorded for [rentorId].
  Future<bool> hasBillBeenTracked(String rentorId, String billId) =>
      _db.billNotificationTrackerExists(rentorId: rentorId, billId: billId);

  /// Inserts a tracker row for the given (rentor, bill) pair.
  Future<void> trackBill({
    required String rentorId,
    required String billId,
    required String billType,
    required int month,
    required int year,
  }) async {
    await _db.insertBillNotificationTracker(
      BillNotificationTracker(
        rentorId: rentorId,
        billId: billId,
        billType: billType,
        month: month,
        year: year,
        receivedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Returns all tracker rows for [rentorId] in [month]/[year].
  Future<List<BillNotificationTracker>> getTrackedBills({
    required String rentorId,
    required int month,
    required int year,
  }) =>
      _db.getBillNotificationTrackers(
          rentorId: rentorId, month: month, year: year);

  /// Returns `true` if a compose notification has already been sent for the
  /// given [rentorId]/[month]/[year]/[billGroup] combination.
  Future<bool> hasComposeNotificationBeenSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) =>
      _db.hasComposeNotificationLog(
          rentorId: rentorId, month: month, year: year, billGroup: billGroup);

  /// Records that a compose notification was sent for [rentorId]/[month]/[year]/[billGroup].
  Future<void> logComposeNotificationSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async {
    await _db.insertComposeNotificationLog(
        rentorId: rentorId, month: month, year: year, billGroup: billGroup);
  }
}
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/helpers/bill_readiness/bill_notification_tracker_helper.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/helpers/bill_readiness/bill_notification_tracker_helper.dart
git commit -m "feat: add BillNotificationTrackerHelper singleton"
```

---

### Task 4: `BillReadinessService` (TDD)

**Files:**
- Create: `lib/services/bill_readiness/bill_readiness_service.dart`
- Create: `test/services/bill_readiness/bill_readiness_service_test.dart`

**Context:** `BillSummaryService` is already complete and used here. `BillNotificationTrackerHelper` accepts subclassing (via `.internal()` constructor) for fake injection in tests.

A bill type is **complete** when: (a) at least one eligible bill of that type exists AND (b) every billId of that type appears in the tracker. A type with zero eligible bills is never complete. The **regular group** is complete when all non-water types in `rentor.billPercentages.keys` are complete. The **water group** is complete when all eligible water bills appear in the tracker.

- [ ] **Step 1: Write the test file**

Write `test/services/bill_readiness/bill_readiness_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/bill_notification_tracker.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/helpers/bill_readiness/bill_notification_tracker_helper.dart';
import 'package:utility_bills_manager/services/bill_readiness/bill_readiness_service.dart';

// ── Fake helper ─────────────────────────────────────────────────────────────

class FakeTrackerHelper extends BillNotificationTrackerHelper {
  FakeTrackerHelper() : super.internal();

  final Set<String> _tracked = {}; // '$rentorId:$billId'
  final Set<String> _logged = {}; // '$rentorId:$month:$year:$group'

  @override
  Future<bool> hasBillBeenTracked(String rentorId, String billId) async =>
      _tracked.contains('$rentorId:$billId');

  @override
  Future<void> trackBill({
    required String rentorId,
    required String billId,
    required String billType,
    required int month,
    required int year,
  }) async {
    _tracked.add('$rentorId:$billId');
  }

  @override
  Future<List<BillNotificationTracker>> getTrackedBills({
    required String rentorId,
    required int month,
    required int year,
  }) async {
    return _tracked
        .where((k) => k.startsWith('$rentorId:'))
        .map((k) => BillNotificationTracker(
              rentorId: rentorId,
              billId: k.split(':')[1],
              billType: 'unknown',
              month: month,
              year: year,
              receivedAt: '',
            ))
        .toList();
  }

  @override
  Future<bool> hasComposeNotificationBeenSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async =>
      _logged.contains('$rentorId:$month:$year:$billGroup');

  @override
  Future<void> logComposeNotificationSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async {
    _logged.add('$rentorId:$month:$year:$billGroup');
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Bill _bill({
  required String billId,
  required BillType type,
  DateTime? dueDate,
  PaymentStatus status = PaymentStatus.unpaid,
}) =>
    Bill(
      billId: billId,
      company: 'Test Co',
      type: type,
      amount: 100.0,
      dueDate: dueDate ?? DateTime(2026, 4, 15),
      status: status,
      notes: null,
    );

Rentor _rentor({
  required String rentorId,
  required Map<BillType, double> billPercentages,
  List<BillType> excludedBillTypes = const [],
}) =>
    Rentor(
      rentorId: rentorId,
      name: 'Test Rentor',
      defaultPercentage: 30.0,
      billPercentages: billPercentages,
      excludedBillTypes: excludedBillTypes,
    );

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late FakeTrackerHelper fakeHelper;
  late BillReadinessService service;
  // April 2026
  final now = DateTime(2026, 4, 10);

  setUp(() {
    fakeHelper = FakeTrackerHelper();
    service = BillReadinessService.forTesting(fakeHelper);
  });

  group('checkReadiness — rentor filtering', () {
    test('returns empty when rentor does not include incoming bill type', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35},
      );
      final bill = _bill(billId: 'b1', type: BillType.gas);

      final result = await service.checkReadiness(
        bill, [rentor], [bill], now: now,
      );

      expect(result, isEmpty);
    });

    test('returns empty when rentor excludes incoming bill type', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.gas: 35},
        excludedBillTypes: [BillType.gas],
      );
      final bill = _bill(billId: 'b1', type: BillType.gas);

      final result = await service.checkReadiness(
        bill, [rentor], [bill], now: now,
      );

      expect(result, isEmpty);
    });
  });

  group('checkReadiness — tracker insertion', () {
    test('inserts tracker row for relevant rentor', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final incoming = _bill(billId: 'b1', type: BillType.electric);

      await service.checkReadiness(
        incoming, [rentor], [incoming], now: now,
      );

      expect(
        await fakeHelper.hasBillBeenTracked('r1', 'b1'),
        isTrue,
      );
    });

    test('does not insert duplicate tracker row', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35},
      );
      final bill = _bill(billId: 'b1', type: BillType.electric);

      // First call — inserts
      await service.checkReadiness(bill, [rentor], [bill], now: now);
      // Second call — should not re-insert (fake tracks via Set, so idempotent)
      await service.checkReadiness(bill, [rentor], [bill], now: now);

      // Only one entry in the set
      final tracked = await fakeHelper.getTrackedBills(
          rentorId: 'r1', month: 4, year: 2026);
      expect(tracked.length, equals(1));
    });
  });

  group('checkReadiness — regular bill completeness', () {
    test('returns empty when a required bill type has no eligible bills yet', () async {
      // rentor needs electric + gas, but only electric has arrived
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final electricBill = _bill(billId: 'b1', type: BillType.electric);

      final result = await service.checkReadiness(
        electricBill, [rentor], [electricBill], now: now,
      );

      expect(result, isEmpty);
    });

    test('returns empty when not all bills of a type are tracked', () async {
      // 2 gas bills; only 1 has been notified
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);
      final gas1 = _bill(billId: 'b2', type: BillType.gas);
      final gas2 = _bill(billId: 'b3', type: BillType.gas);
      final allBills = [electric, gas1, gas2];

      // Mark electric and gas1 as tracked
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b2', billType: 'gas', month: 4, year: 2026);

      // Incoming: gas2 (not yet tracked)
      final result = await service.checkReadiness(
        gas2, [rentor], allBills, now: now,
      );

      expect(result, isEmpty);
    });

    test('returns ComposeNotification when all regular types are fully tracked', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);
      final gas1 = _bill(billId: 'b2', type: BillType.gas);
      final gas2 = _bill(billId: 'b3', type: BillType.gas);
      final allBills = [electric, gas1, gas2];

      // Pre-track electric and gas1
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b2', billType: 'gas', month: 4, year: 2026);

      // Incoming: gas2 — completes coverage
      final result = await service.checkReadiness(
        gas2, [rentor], allBills, now: now,
      );

      expect(result.length, equals(1));
      expect(result.first.isWater, isFalse);
      expect(result.first.rentor.rentorId, equals('r1'));
      expect(result.first.bills.map((b) => b.billId),
          containsAll(['b1', 'b2', 'b3']));
    });

    test('does not return duplicate when log row already exists', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);

      // Pre-track bill and log sent
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.logComposeNotificationSent(
          rentorId: 'r1', month: 4, year: 2026, billGroup: 'regular');

      final result = await service.checkReadiness(
        electric, [rentor], [electric], now: now,
      );

      expect(result, isEmpty);
    });
  });

  group('checkReadiness — water bill completeness', () {
    test('returns water ComposeNotification when all water bills tracked', () async {
      // Water bills are eligible when due in the next month (May 2026 when now = April 2026)
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.water: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);
      final water = _bill(
          billId: 'b2',
          type: BillType.water,
          dueDate: DateTime(2026, 5, 1)); // due next month — eligible

      final allBills = [electric, water];

      // Pre-track electric so regular group is not triggered
      // (electric is the only regular type; it's complete)
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.logComposeNotificationSent(
          rentorId: 'r1', month: 4, year: 2026, billGroup: 'regular');

      // Incoming: water bill
      final result = await service.checkReadiness(
        water, [rentor], allBills, now: now,
      );

      expect(result.length, equals(1));
      expect(result.first.isWater, isTrue);
      expect(result.first.bills.map((b) => b.billId), contains('b2'));
    });

    test('does not trigger water notification when rentor has no water in billPercentages', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35},
      );
      final water = _bill(
          billId: 'b1',
          type: BillType.water,
          dueDate: DateTime(2026, 5, 1));

      final result = await service.checkReadiness(
        water, [rentor], [water], now: now,
      );

      expect(result, isEmpty);
    });

    test('water not triggered when not all water bills tracked', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.water: 35},
      );
      final water1 =
          _bill(billId: 'b1', type: BillType.water, dueDate: DateTime(2026, 5, 1));
      final water2 =
          _bill(billId: 'b2', type: BillType.water, dueDate: DateTime(2026, 5, 1));

      // Pre-track water1 only
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'water', month: 4, year: 2026);

      // Incoming: water2 — not all tracked yet
      final result = await service.checkReadiness(
        water2, [rentor], [water1, water2], now: now,
      );

      expect(result, isEmpty);
    });
  });

  group('checkReadiness — multi-rentor', () {
    test('returns notification only for the complete rentor', () async {
      final john = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final amy = _rentor(
        rentorId: 'r2',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);
      final gas = _bill(billId: 'b2', type: BillType.gas);

      // John has both tracked; Amy only has electric
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b2', billType: 'gas', month: 4, year: 2026);
      await fakeHelper.trackBill(
          rentorId: 'r2', billId: 'b1', billType: 'electric', month: 4, year: 2026);

      // Incoming: gas (for both rentors, since both have gas in billPercentages)
      final result = await service.checkReadiness(
        gas, [john, amy], [electric, gas], now: now,
      );

      // Only John is complete (Amy just got gas tracked, but gas was already
      // tracked for John before this call)
      expect(result.length, equals(1));
      expect(result.first.rentor.rentorId, equals('r1'));
    });
  });

  group('checkReadiness — December/January boundary', () {
    test('water due in January is eligible when now is December', () async {
      final decNow = DateTime(2026, 12, 10);
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.water: 35},
      );
      final janWater = _bill(
          billId: 'b1',
          type: BillType.water,
          dueDate: DateTime(2027, 1, 5)); // next month = Jan 2027

      final result = await service.checkReadiness(
        janWater, [rentor], [janWater], now: decNow,
      );

      expect(result.length, equals(1));
      expect(result.first.isWater, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
flutter test test/services/bill_readiness/bill_readiness_service_test.dart
```
Expected: FAIL — `bill_readiness_service.dart` does not exist.

- [ ] **Step 3: Create `BillReadinessService`**

Write `lib/services/bill_readiness/bill_readiness_service.dart`:

```dart
import '../bill_summary/bill_summary_service.dart';
import '../../data/models/bill.dart';
import '../../data/models/rentor.dart';
import '../../helpers/bill_readiness/bill_notification_tracker_helper.dart';

/// Returned by [BillReadinessService.checkReadiness] when a rentor's bills are
/// all accounted for and a compose message notification should be shown.
class ComposeNotification {
  final Rentor rentor;

  /// The eligible bills to include in the generated message.
  final List<Bill> bills;

  /// `true` → water group; `false` → regular group.
  final bool isWater;

  const ComposeNotification({
    required this.rentor,
    required this.bills,
    required this.isWater,
  });
}

/// Singleton that checks whether all expected bills for a rentor have been
/// received via notification and returns [ComposeNotification]s when they have.
///
/// Inject [BillNotificationTrackerHelper] via [BillReadinessService.forTesting]
/// to avoid SQLite in unit tests.
class BillReadinessService {
  static final BillReadinessService _instance =
      BillReadinessService._internal();

  factory BillReadinessService() => _instance;

  BillReadinessService._internal()
      : _trackerHelper = BillNotificationTrackerHelper();

  /// Test-only constructor — injects a fake [BillNotificationTrackerHelper].
  BillReadinessService.forTesting(BillNotificationTrackerHelper trackerHelper)
      : _trackerHelper = trackerHelper;

  final BillNotificationTrackerHelper _trackerHelper;
  final BillSummaryService _summaryService = BillSummaryService();

  /// Records receipt of [newBill] for all relevant rentors and returns any
  /// compose notifications that should be displayed.
  ///
  /// The caller must:
  /// 1. Persist [newBill] and reload repositories before calling this.
  /// 2. Call [BillNotificationTrackerHelper.logComposeNotificationSent] and
  ///    show each returned notification.
  ///
  /// [now] is injectable for deterministic testing.
  Future<List<ComposeNotification>> checkReadiness(
    Bill newBill,
    List<Rentor> allRentors,
    List<Bill> allBills, {
    DateTime? now,
  }) async {
    final ref = now ?? DateTime.now();
    final results = <ComposeNotification>[];

    final relevantRentors = allRentors.where((r) =>
        r.billPercentages.containsKey(newBill.type) &&
        !r.excludedBillTypes.contains(newBill.type));

    for (final rentor in relevantRentors) {
      // Record receipt once.
      final alreadyTracked =
          await _trackerHelper.hasBillBeenTracked(rentor.rentorId, newBill.billId);
      if (!alreadyTracked) {
        await _trackerHelper.trackBill(
          rentorId: rentor.rentorId,
          billId: newBill.billId,
          billType: newBill.type.name,
          month: ref.month,
          year: ref.year,
        );
      }

      final trackedRows = await _trackerHelper.getTrackedBills(
        rentorId: rentor.rentorId,
        month: ref.month,
        year: ref.year,
      );
      final trackedIds = trackedRows.map((t) => t.billId).toSet();

      final eligibleBills =
          _summaryService.getEligibleBills(rentor, allBills, now: ref);
      final regularBills =
          eligibleBills.where((b) => b.type != BillType.water).toList();
      final waterBills =
          eligibleBills.where((b) => b.type == BillType.water).toList();

      // Regular group
      final regularSent = await _trackerHelper.hasComposeNotificationBeenSent(
        rentorId: rentor.rentorId,
        month: ref.month,
        year: ref.year,
        billGroup: 'regular',
      );
      if (!regularSent &&
          _isRegularGroupComplete(rentor, regularBills, trackedIds)) {
        results.add(
            ComposeNotification(rentor: rentor, bills: regularBills, isWater: false));
      }

      // Water group (only if rentor has water configured)
      if (rentor.billPercentages.containsKey(BillType.water)) {
        final waterSent = await _trackerHelper.hasComposeNotificationBeenSent(
          rentorId: rentor.rentorId,
          month: ref.month,
          year: ref.year,
          billGroup: 'water',
        );
        if (!waterSent && _isWaterGroupComplete(waterBills, trackedIds)) {
          results.add(
              ComposeNotification(rentor: rentor, bills: waterBills, isWater: true));
        }
      }
    }

    return results;
  }

  /// Returns `true` when every non-water type in [rentor.billPercentages] has
  /// at least one eligible bill AND every eligible bill of that type is tracked.
  bool _isRegularGroupComplete(
    Rentor rentor,
    List<Bill> regularBills,
    Set<String> trackedIds,
  ) {
    final requiredTypes = rentor.billPercentages.keys
        .where((t) => t != BillType.water)
        .toList();

    if (requiredTypes.isEmpty) return false;

    for (final billType in requiredTypes) {
      final billsOfType =
          regularBills.where((b) => b.type == billType).toList();
      if (billsOfType.isEmpty) return false; // still waiting for this type
      if (billsOfType.any((b) => !trackedIds.contains(b.billId))) return false;
    }
    return true;
  }

  /// Returns `true` when [waterBills] is non-empty and every water bill is
  /// tracked.
  bool _isWaterGroupComplete(
    List<Bill> waterBills,
    Set<String> trackedIds,
  ) {
    if (waterBills.isEmpty) return false;
    return waterBills.every((b) => trackedIds.contains(b.billId));
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
flutter test test/services/bill_readiness/bill_readiness_service_test.dart
```
Expected: All 10 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/bill_readiness/bill_readiness_service.dart \
        test/services/bill_readiness/bill_readiness_service_test.dart
git commit -m "feat: add BillReadinessService with ComposeNotification (TDD)"
```

---

### Task 5: Update `NotificationService` interface

**Files:**
- Modify: `lib/services/notification/notification_service.dart`

Add two abstract methods so both native and web implementations can be called uniformly from `main.dart`.

- [ ] **Step 1: Read the file**

Read `lib/services/notification/notification_service.dart` in full.

- [ ] **Step 2: Add import and two abstract methods**

Find:
```dart
import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../data/models/sse_event.dart';
```

Replace with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/sse_event.dart';
```

Find:
```dart
    //region Lifecycle
    Future<void> initialize();

    void dispose();
    //endregion
```

Replace with:

```dart
    //region Lifecycle
    Future<void> initialize();

    void dispose();

    /// Registers the [GlobalKey<NavigatorState>] used by the notification tap
    /// handler to navigate to [MessagePreviewScreen].
    /// No-op on platforms that do not support tap navigation (web).
    void setNavigatorKey(GlobalKey<NavigatorState> key);

    /// Checks whether the app was cold-started via a compose notification tap
    /// and navigates to [MessagePreviewScreen] if so.
    /// No-op on platforms without local-notification tap support (web).
    Future<void> handleLaunchNotification();
    //endregion
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/services/notification/notification_service.dart
```
Expected: no errors (there will be `unimplemented` warnings for the two concrete classes — those are fixed in the next two steps).

- [ ] **Step 4: Commit**

```bash
git add lib/services/notification/notification_service.dart
git commit -m "feat: add setNavigatorKey and handleLaunchNotification to NotificationService interface"
```

---

### Task 6: Update `NativeNotificationService` — readiness check + tap navigation

**Files:**
- Modify: `lib/services/notification/notification_service_native.dart`

**Context:** `handleSseEvent` is currently a synchronous `void` method. The interface declares it as `void`, so we keep the signature and spawn an internal async helper. The navigator key is stored as a nullable field and set via `setNavigatorKey`. `_showComposeNotification` sends a local notification whose JSON payload encodes `rentorId`, `billIds`, and `isWater`.

- [ ] **Step 1: Read the file**

Read `lib/services/notification/notification_service_native.dart` in full.

- [ ] **Step 2: Add imports**

Find:
```dart
import 'app_notification_store.dart';
import 'sse_service_native.dart';
import '../api/api_service.dart';
import '../../config/app_config.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/sse_event.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../services/notification/notification_service.dart';
import '../../utils/app_logger.dart';
```

Replace with:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_notification_store.dart';
import 'sse_service_native.dart';
import '../api/api_service.dart';
import '../bill_readiness/bill_readiness_service.dart';
import '../bill_summary/bill_summary_service.dart';
import '../../config/app_config.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/bill.dart';
import '../../data/models/rentor.dart';
import '../../data/models/sse_event.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../data/repositories/rentors_repository.dart';
import '../../helpers/bill_readiness/bill_notification_tracker_helper.dart';
import '../../screens/bill_summary/message_preview_screen.dart';
import '../../services/notification/notification_service.dart';
import '../../utils/app_logger.dart';
```

- [ ] **Step 3: Add `_navigatorKey` field and `_trackerHelper` field**

Find:
```dart
  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription? _tokenRefreshSubscription;
```

Replace with:

```dart
  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription? _tokenRefreshSubscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  final _trackerHelper = BillNotificationTrackerHelper();
```

- [ ] **Step 4: Add `setNavigatorKey` and `handleLaunchNotification` implementations**

Find:
```dart
  @override
  void dispose() {
```

Insert the following block immediately **before** that line:

```dart
  @override
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  @override
  Future<void> handleLaunchNotification() async {
    final details =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTap(details?.notificationResponse?.payload);
      });
    }
  }

```

- [ ] **Step 5: Add `onDidReceiveNotificationResponse` to `initLocalNotifications`**

Find:
```dart
    await _localNotifications.initialize(settings: initSettings);
```

Replace with:

```dart
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response.payload);
      },
    );
```

- [ ] **Step 6: Replace `handleSseEvent` with async-dispatching version**

Find:
```dart
  @override
  void handleSseEvent(SseEvent event) {
    final title = switch (event.type) {
      SseEventType.newBill => 'New Bill',
      SseEventType.newPayment => 'New Payment',
    };

    AppLogger().d('[SSE] ${event.type}: $title');
    showNotification(title: title, body: event.message);
    addToStore(type: event.type, title: title, body: event.message);
    reloadRepository(event.type);
  }
```

Replace with:

```dart
  @override
  void handleSseEvent(SseEvent event) {
    // Dispatch async work without blocking the SSE stream.
    _handleSseEventAsync(event);
  }

  Future<void> _handleSseEventAsync(SseEvent event) async {
    try {
      final title = switch (event.type) {
        SseEventType.newBill => 'New Bill',
        SseEventType.newPayment => 'New Payment',
      };

      AppLogger().d('[SSE] ${event.type}: $title');
      await showNotification(title: title, body: event.message);
      addToStore(type: event.type, title: title, body: event.message);

      // Await the reload so bills/rentors are current before readiness check.
      await _reloadRepositoryAsync(event.type);

      if (event.type == SseEventType.newBill) {
        final bill = Bill.fromJson(event.data);

        if (RentorsRepository().rentors.isEmpty) {
          await RentorsRepository().reload();
        }
        final allRentors = RentorsRepository().rentors;
        final allBills = BillsRepository().bills;

        final composeNotifications = await BillReadinessService()
            .checkReadiness(bill, allRentors, allBills);

        final now = DateTime.now();
        for (final cn in composeNotifications) {
          await _trackerHelper.logComposeNotificationSent(
            rentorId: cn.rentor.rentorId,
            month: now.month,
            year: now.year,
            billGroup: cn.isWater ? 'water' : 'regular',
          );
          await _showComposeNotification(cn);
        }
      }
    } catch (e) {
      AppLogger().e('[NotificationService] SSE handling error: $e', error: e);
    }
  }

  Future<void> _reloadRepositoryAsync(SseEventType type) async {
    switch (type) {
      case SseEventType.newBill:
        await BillsRepository().reload();
      case SseEventType.newPayment:
        await PaymentsRepository().reload();
    }
  }
```

- [ ] **Step 7: Add `_showComposeNotification` and `_handleNotificationTap`**

Find the `//region FCM` line that follows the SSE region, and insert the following two methods immediately **before** it:

```dart
  Future<void> _showComposeNotification(ComposeNotification cn) async {
    if (defaultTargetPlatform == TargetPlatform.windows) return;

    final firstName = cn.rentor.name.split(' ').first;
    final title = cn.isWater
        ? 'Water bill ready for $firstName'
        : 'Compose bill summary for $firstName';
    final body = cn.isWater
        ? 'Tap to compose water bill message'
        : 'All bills received — tap to generate message';
    final payload = jsonEncode({
      'rentorId': cn.rentor.rentorId,
      'billIds': cn.bills.map((b) => b.billId).toList(),
      'isWater': cn.isWater,
    });

    await _localNotifications.show(
      cn.rentor.rentorId.hashCode ^ (cn.isWater ? 1 : 0),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> _handleNotificationTap(String? payload) async {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final rentorId = data['rentorId'] as String;
      final billIds = (data['billIds'] as List).cast<String>();

      if (RentorsRepository().rentors.isEmpty) {
        await RentorsRepository().reload();
      }
      Rentor? rentor = RentorsRepository().rentors
          .cast<Rentor?>()
          .firstWhere((r) => r?.rentorId == rentorId, orElse: () => null);
      if (rentor == null) return;

      await BillsRepository().reload();
      final bills = BillsRepository().bills
          .where((b) => billIds.contains(b.billId))
          .toList();
      if (bills.isEmpty) return;

      final message = BillSummaryService().generateMessage(rentor, bills);

      _navigatorKey?.currentState?.push(
        MaterialPageRoute(
          builder: (_) => MessagePreviewScreen(initialMessage: message),
        ),
      );
    } catch (e) {
      AppLogger().e('[NotificationService] Tap handling error: $e', error: e);
    }
  }

```

- [ ] **Step 8: Verify**

```bash
flutter analyze lib/services/notification/notification_service_native.dart
```
Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/services/notification/notification_service_native.dart
git commit -m "feat: wire BillReadinessService into NativeNotificationService with tap navigation"
```

---

### Task 7: Update `WebNotificationService` — no-op stubs

**Files:**
- Modify: `lib/services/notification/notification_service_web.dart`

Web does not use `flutter_local_notifications`, so both new interface methods are no-ops.

- [ ] **Step 1: Read the file**

Read `lib/services/notification/notification_service_web.dart` in full.

- [ ] **Step 2: Add import**

Find:
```dart
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;
```

Replace with:

```dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;
```

- [ ] **Step 3: Add no-op implementations after `dispose()`**

Find:
```dart
  @override
  void dispose() {
```

Locate the closing `}` of `dispose()` and insert the following block immediately after it:

```dart

  @override
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    // Not supported on web — web uses browser URL navigation.
  }

  @override
  Future<void> handleLaunchNotification() async {
    // Not supported on web.
  }
```

- [ ] **Step 4: Verify**

```bash
flutter analyze lib/services/notification/notification_service_web.dart
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/services/notification/notification_service_web.dart
git commit -m "feat: add no-op setNavigatorKey and handleLaunchNotification to WebNotificationService"
```

---

### Task 8: Update `main.dart` — navigator key + cold-start

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Read the file**

Read `lib/main.dart` in full.

- [ ] **Step 2: Add navigator key declaration**

Find:
```dart
final notificationService = createNotificationService();
```

Replace with:

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final notificationService = createNotificationService();
```

- [ ] **Step 3: Register key and handle cold-start after `notificationService.initialize()`**

Find:
```dart
  await notificationService.initialize();

  runApp(const MyApp());
```

Replace with:

```dart
  await notificationService.initialize();

  notificationService.setNavigatorKey(navigatorKey);
  await notificationService.handleLaunchNotification();

  runApp(const MyApp());
```

- [ ] **Step 4: Pass navigator key to `MaterialApp`**

Find:
```dart
    return MaterialApp(
      title: 'Utility Bill Manager',
```

Replace with:

```dart
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Utility Bill Manager',
```

- [ ] **Step 5: Verify**

```bash
flutter analyze lib/main.dart
```
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register navigator key and handle cold-start compose notification tap"
```

---

### Task 9: Full test suite + update TODO + update PR

- [ ] **Step 1: Run the full test suite**

```bash
flutter test
```
Expected: all tests pass.

- [ ] **Step 2: Update `TODO.md`**

The rentor messaging section is already partially updated. Under `## Rentor Messaging`, the sub-item for `Support templating for customizable messages` should remain unchecked (not implemented). No changes needed to TODO.md beyond what was already done in the previous PR commit.

- [ ] **Step 3: Push the branch**

```bash
git push
```

- [ ] **Step 4: Update the PR description**

```bash
gh pr edit 6 --body "$(cat <<'EOF'
## Summary

### Rentor Bill Summary Messaging
- Adds `BillSummaryService` — pure singleton that filters eligible bills (current month, unpaid, not excluded), generates greeting-aware bill summary messages, with water bill handled separately (due next month)
- Adds `BillSelectionScreen` — Step 1 wizard: checkbox list of eligible bills, pre-checked, with "Generate Message" button
- Adds `MessagePreviewScreen` — Step 2 wizard: editable message TextField with share_plus share sheet (clipboard fallback when unavailable)
- Modifies `AddEditRentorScreen` — adds "Send Bill Summary" button (edit mode only); greyed out with settled snackbar when rentor owes nothing this month
- 30 unit tests for `BillSummaryService`

### Bill Readiness Notification
- Adds `BillNotificationTracker` model + SQLite table (schema v17) — tracks per-(rentor, bill) notification receipt
- Adds `BillComposeNotificationLog` table — prevents duplicate compose notifications per rentor per month
- Both tables use `ON DELETE CASCADE` foreign keys to rentors and bills
- Adds `BillNotificationTrackerHelper` singleton — SQLite CRUD for both tables
- Adds `BillReadinessService` — after each new-bill SSE event, checks whether all expected bills per rentor have arrived; returns `ComposeNotification` for each complete group
- Modifies `NativeNotificationService` — async SSE handling, shows compose notification with JSON payload, handles tap to navigate to `MessagePreviewScreen`
- Modifies `main.dart` — registers `GlobalKey<NavigatorState>`, handles cold-start notification tap
- 10 unit tests for `BillReadinessService`

## Test plan

- [ ] Run `flutter test` — all tests pass
- [ ] Open an existing rentor with unpaid bills this month → "Send Bill Summary" button is enabled → tapping opens bill selection
- [ ] Select bills → tap "Generate Message" → message preview screen shows correct formatted message
- [ ] Edit message → tap Share → system share sheet opens
- [ ] Open an existing rentor with no unpaid bills → button is greyed out → tapping shows "[name] is settled for this month" snackbar
- [ ] Creating a new rentor → no "Send Bill Summary" button shown
- [ ] Simulate new-bill SSE notifications arriving for all bill types a rentor is configured for → compose notification appears
- [ ] Tap the compose notification → app navigates to MessagePreviewScreen with pre-generated message
- [ ] Verify compose notification is not shown a second time for the same rentor/month
- [ ] Verify water bill triggers a separate compose notification
- [ ] Delete a rentor → confirm tracker rows are also deleted (SQLite cascade)
- [ ] Delete a bill → confirm tracker rows for that bill are also deleted (SQLite cascade)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---
