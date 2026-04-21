# Design: Bill Readiness Notification

**Date:** 2026-04-20
**Status:** Approved

---

## Problem

When bill notifications arrive throughout the month, the landlord has to manually decide when all bills for a given rentor have been received and it is time to compose a summary message. This feature automates that signal: once every bill of every type a rentor is configured for has been received via notification, the app sends a local notification prompting the landlord to compose and send a bill summary to that rentor.

---

## Scope

**Created:** 4 files

| File | Purpose |
|---|---|
| `lib/data/models/bill_notification_tracker.dart` | Model for tracker table rows |
| `lib/helpers/bill_readiness/bill_notification_tracker_helper.dart` | SQLite CRUD singleton for both new tables |
| `lib/services/bill_readiness/bill_readiness_service.dart` | Core readiness-check logic |
| `test/services/bill_readiness/bill_readiness_service_test.dart` | Unit tests |

**Modified:** 3 files

| File | Change |
|---|---|
| `lib/helpers/database/database_helper.dart` | Bump to schema v17, add two new tables + migration |
| `lib/services/notification/notification_service_native.dart` | Call `BillReadinessService.checkReadiness` after each new-bill SSE event |
| `lib/main.dart` | Register `GlobalKey<NavigatorState>`, handle cold-start notification tap |

---

## Data Model & Storage

### Schema version bump: 16 → **17**

### Table: `bill_notification_tracker`

One row per (rentor, bill) pair inserted when a bill notification is received.

```sql
CREATE TABLE bill_notification_tracker (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  rentorId   TEXT NOT NULL REFERENCES rentors(rentorId) ON DELETE CASCADE,
  billId     TEXT NOT NULL REFERENCES bills(billId)     ON DELETE CASCADE,
  billType   TEXT NOT NULL,
  month      INTEGER NOT NULL,
  year       INTEGER NOT NULL,
  receivedAt TEXT NOT NULL
);
```

### Table: `bill_compose_notification_log`

One row per sent compose notification, used to prevent duplicates within the same month.

```sql
CREATE TABLE bill_compose_notification_log (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  rentorId  TEXT NOT NULL REFERENCES rentors(rentorId) ON DELETE CASCADE,
  month     INTEGER NOT NULL,
  year      INTEGER NOT NULL,
  billGroup TEXT NOT NULL,  -- 'regular' | 'water'
  sentAt    TEXT NOT NULL
);
```

### State reset

Both tables are month-scoped by `month` and `year` columns. All queries filter on the current calendar month and year. Old rows are never read and do not need cleanup — they accumulate silently. The tracking state for a new month begins automatically with no action required.

### Foreign key enforcement

`PRAGMA foreign_keys = ON` must be set on each database connection. The `DatabaseHelper` must be verified to enable this, and added if not already present.

---

## BillReadinessService

### API

```dart
class BillReadinessService {
  static final BillReadinessService _instance = BillReadinessService._internal();
  factory BillReadinessService() => _instance;
  BillReadinessService._internal();

  /// Records receipt of [newBill] for all relevant rentors and returns any
  /// compose notifications that should be shown.
  ///
  /// [allRentors] and [allBills] are the full current state from the
  /// repositories after the new bill has been persisted.
  ///
  /// [now] is injectable for testing.
  Future<List<ComposeNotification>> checkReadiness(
    Bill newBill,
    List<Rentor> allRentors,
    List<Bill> allBills, {
    DateTime? now,
  }) async { ... }
}

class ComposeNotification {
  final Rentor rentor;
  final List<Bill> bills;   // bills to use for message generation
  final bool isWater;       // true → water group; false → regular group
}
```

### Logic

For each call to `checkReadiness(newBill, allRentors, allBills)`:

1. **Find relevant rentors** — filter `allRentors` to those whose `billPercentages.keys` contains `newBill.type`.

2. **Record receipt** — for each relevant rentor, insert a row into `bill_notification_tracker` for `(rentorId, billId, billType, month, year)` if that pair does not already exist.

3. **Determine bill group** — `newBill.type == BillType.water` → check water group; else check regular group (also check water group if the rentor has water in `billPercentages` and the incoming bill happens to be water).

4. **Completeness check — regular**:
   - Get all eligible non-water bills for this rentor: `BillSummaryService().getEligibleBills(rentor, allBills, now: now)` filtered to `type != BillType.water`.
   - Group by `BillType`. For each type, collect all `billId`s.
   - Query `bill_notification_tracker` for this rentor/month/year.
   - A type is **complete** when: (a) at least one eligible bill of that type exists, AND (b) every `billId` of that type appears in the tracker. A type with zero eligible bills is never considered complete — we wait for bills of that type to arrive.
   - Regular group is complete when **all** non-water types in `rentor.billPercentages.keys` are complete.
   - If complete AND no `bill_compose_notification_log` row exists for `(rentorId, month, year, 'regular')` → add `ComposeNotification(rentor, regularBills, isWater: false)` to results.

5. **Completeness check — water** (only if rentor's `billPercentages.keys` includes `BillType.water`):
   - Get all eligible water bills for this rentor.
   - Check every water `billId` appears in the tracker.
   - If complete AND no log row for `(rentorId, month, year, 'water')` → add `ComposeNotification(rentor, waterBills, isWater: true)` to results.

6. **Return** `List<ComposeNotification>` (empty if nothing triggered).

The **caller** is responsible for:
- Inserting the corresponding `bill_compose_notification_log` rows.
- Showing the local notifications via `flutter_local_notifications`.

---

## Notification Payload & Tap Navigation

### Notification content

| Group | Title | Body |
|---|---|---|
| Regular | `"Compose bill summary for [firstName]"` | `"All bills received — tap to generate message"` |
| Water | `"Water bill ready for [firstName]"` | `"Tap to compose water bill message"` |

### Payload

Each notification carries a JSON string payload:

```json
{ "rentorId": "...", "billIds": ["...", "..."], "isWater": false }
```

Bills are looked up live from the DB on tap so the generated message always reflects current amounts.

### Navigation

A `GlobalKey<NavigatorState> navigatorKey` is declared at app level and passed to `MaterialApp(navigatorKey: navigatorKey)`.

When `onDidReceiveNotificationResponse` fires (foreground or background resume):

1. Decode the JSON payload.
2. Fetch rentor by `rentorId` and bills by `billIds` from the DB.
3. Call `BillSummaryService().generateMessage(rentor, bills)`.
4. Push `MessagePreviewScreen(initialMessage: message)` via `navigatorKey.currentState!.push(...)`.

### Cold-start (app terminated)

In `main.dart`, after app initialisation, call:

```dart
final details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
if (details?.didNotificationLaunchApp == true) {
  // decode payload and schedule post-frame navigation to MessagePreviewScreen
  WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotificationLaunch(details!.notificationResponse));
}
```

---

## Integration: `notification_service_native.dart`

After the existing `handleSseEvent` logic (persist bill, add to `AppNotificationStore`, reload repository), add:

```dart
if (event.type == SseEventType.newBill) {
  final bill = Bill.fromJson(event.data);
  final allRentors = /* load from RentorsRepository */;
  final allBills   = /* load from BillsRepository */;
  final notifications = await BillReadinessService()
      .checkReadiness(bill, allRentors, allBills);
  for (final cn in notifications) {
    await _trackerHelper.logComposeNotificationSent(
      cn.rentor.rentorId, now.month, now.year,
      cn.isWater ? 'water' : 'regular',
    );
    await _showComposeLocalNotification(cn);
  }
}
```

`_showComposeLocalNotification` builds the notification title/body and serialises the payload JSON using `flutter_local_notifications`.

---

## Eligibility Rules (inherited from BillSummaryService)

`BillReadinessService` reuses `BillSummaryService.getEligibleBills` to determine which bills are in scope. This means the same rules apply:

- `bill.status != PaymentStatus.paid`
- `bill.type` not in `rentor.excludedBillTypes`
- Regular bills: `bill.dueDate` in the current calendar month
- Water bills: `bill.dueDate` in the current or next calendar month

---

## Testing

Unit tests for `BillReadinessService` (no DB — use fakes for helper dependencies):

- `checkReadiness` returns empty when rentor does not include incoming bill type
- `checkReadiness` inserts a tracker row for a relevant rentor
- `checkReadiness` returns empty when regular types are not yet fully covered
- `checkReadiness` returns `ComposeNotification` when all regular bill types are fully tracked
- `checkReadiness` does not return duplicate notifications if log row already exists
- `checkReadiness` handles multiple bills of the same type (all must be tracked)
- Water group: returns water `ComposeNotification` when all water bills tracked
- Water group: does not trigger when rentor does not include water in `billPercentages`
- December → January boundary: year rolls over correctly for month/year scoping
- `checkReadiness` is independent per rentor (one rentor complete does not affect another)
