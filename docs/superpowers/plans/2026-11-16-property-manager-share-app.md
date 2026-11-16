# Property Manager Share (App) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's hardcoded 30%/50% "considered paid" thresholds with the computed Property Manager share, add a rentor start date (model, DB, form), honour it in owed amounts and eligibility, re-check bill statuses on rentor save in server mode, and show a read-only Property Manager card.

**Architecture:** Port the server's `PropertyManagerShare` utility to `lib/utils/bills/property_manager_share.dart` with the **identical API**. `Rentor` gains `startDate`, `isActiveOn`, `percentageFor`. `BillsHelper`, `SummaryScreen`, `BillSummaryService` and `BillReadinessService` consume them. A new `PropertyManagerCard` widget renders the current shares.

**Tech Stack:** Flutter, sqflite, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-13-property-manager-share-design.md`

**Prerequisite:** The server PR from `utility_bills_server/docs/superpowers/plans/2026-11-16-property-manager-share-server.md` is merged and deployed. Work happens on the existing `feature/property-manager-share` branch.

## Global Constraints

- Property Manager percentage = `100 − Σ rentor.percentageFor(type)` over rentors where `isActiveOn(bill.dueDate)`; **never rounded** (display formats to 2 decimals only).
- A type is covered only if at least one active rentor does not exclude it; otherwise no threshold.
- Share ≤ 0 → threshold 0 (full payment); the `+ 1.00` dollar tolerance still applies.
- `isActiveOn`: `startDate == null` or `dateOnly(startDate) <= dateOnly(date)`.
- `percentageFor(type)`: excluded → 0; else `billPercentages[type]`; else `defaultPercentage`.
- `startDate` JSON key `startDate`, date-only `yyyy-MM-dd`; DB column `rentors.startDate TEXT`, nullable; DB version 18 → **19**.
- Re-check changes only `status`, never `amountPaid`; skips `unknown` bills and bills due before the affected start date; runs in the app only when `AppConfig.mode == AppMode.server` (the server does it in client mode).
- Bills already `paid` keep displaying as paid on the summary screen (`|| bill.status == PaymentStatus.paid` stays).

## Review Focus

1. Same-day `startDate` vs a bill due later that day → rentor counts. Test in Task 1.
2. Editing an existing rentor whose stored `startDate` is null → the form shows it empty and saving keeps it null (does **not** default to today). Test in Task 5.
3. Client mode: after saving a rentor, bill statuses changed by the server appear without a manual refresh (bills repository reloads). Manual check in Task 4.
4. Rentors total > 100% → the card shows the warning and the share as a negative or zero number, never hides the type. Test in Task 5.
5. A new rentor's bill summary for a month that straddles their start date only lists bills due on/after it. Test in Task 3.

---

### Task 1: Rentor `startDate`, activity, percentage lookup, DB column

**Files:**
- Modify: `lib/data/models/rentor.dart`
- Modify: `lib/helpers/database/database_helper.dart` (CREATE TABLE `rentors` ~line 108, `_databaseVersion` line 33, `_onUpgrade` after `oldVersion < 18` ~line 656, payment JOIN selects ~line 917)
- Create: `test/data/models/rentor_test.dart`

**Interfaces:**
- Produces: `final DateTime? startDate;`, `bool isActiveOn(DateTime date)`, `double percentageFor(BillType type)`; `Rentor.calculateOwedAmount` and `calculateOwedBreakdown` return/skip 0 for bills where `!isActiveOn(bill.dueDate)`.

- [ ] **Step 1: Write failing tests in `test/data/models/rentor_test.dart`**

```dart
test('isActiveOn: null startDate is always active', ...);
test('isActiveOn: same calendar day counts regardless of time', () {
  final r = rentor(startDate: DateTime(2026, 11, 20));
  expect(r.isActiveOn(DateTime(2026, 11, 20, 18)), isTrue);
  expect(r.isActiveOn(DateTime(2026, 11, 19, 23, 59)), isFalse);
});
test('percentageFor: excluded → 0, override → override, else default', ...); // default 15, {gas: 30}, excluded [internet]
test('fromJson/toJson round-trip startDate as yyyy-MM-dd; null stays null', ...);
test('rentorFromJson reads r_startDate', ...);
test('toDbJson includes startDate', ...);
test('calculateOwedAmount: bill due before startDate → 0', ...); // 15%, bill 100 due 2026-11-12, start 2026-11-13
test('calculateOwedAmount: on/after startDate → 15.0', ...);
test('calculateOwedBreakdown skips bills due before startDate', () {
  // bills: electric 100 due 2026-11-12, electric 100 due 2026-11-20; start 2026-11-13; 15%
  // → {electric: 15.0}
});
test('calculateOwedBreakdown with percentageForType still skips pre-start bills', ...);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/models/rentor_test.dart`
Expected: compile errors on `startDate` / `isActiveOn` / `percentageFor`.

- [ ] **Step 3: Implement in `lib/data/models/rentor.dart`**

Add the field and both methods; `startDate` in `fromJson`, `rentorFromJson` (`r_startDate`), and `toJson` (`?.toIso8601String().split('T').first`). `calculateOwedAmount`: `!rentor.isActiveOn(bill.dueDate)` → 0, otherwise use `rentor.percentageFor(bill.type)` (keep the `roundToWholeDollar` param). `calculateOwedBreakdown`: `continue` when `!isActiveOn(bill.dueDate)`, before the percentage lookup. Fix the stale `calculateOwedAmount` doc comment (it does fall back to default).

- [ ] **Step 4: Implement DB changes**

`startDate TEXT` in CREATE TABLE `rentors`; `_databaseVersion = 19`; `if (oldVersion < 19) { await _ensureColumn(db, 'rentors', 'startDate', 'TEXT'); }`; add `'r.startDate AS r_startDate'` to the payment JOIN select list.

- [ ] **Step 5: Run tests and analyzer**

Run: `flutter test test/data/models/rentor_test.dart && flutter analyze`
Expected: tests PASS; no new analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/rentor.dart lib/helpers/database/database_helper.dart test/data/models/rentor_test.dart
git commit -m "feat: add rentor startDate and start-date-aware owed amounts"
```

---

### Task 2: `PropertyManagerShare` utility (port of server)

**Files:**
- Create: `lib/utils/bills/property_manager_share.dart`
- Create: `test/utils/bills/property_manager_share_test.dart`

**Interfaces:**
- Consumes: Task 1's `Rentor` API.
- Produces: the **exact** API from the server plan's Task 2 — `static` members on `class PropertyManagerShare`:
  `double? shareFor(BillType, DateTime asOf, List<Rentor>)`, `Map<BillType, double> sharesAsOf(DateTime, List<Rentor>)`, `double paidAmount(Bill)`, `bool isConsideredPaid(Bill, List<Rentor>)`, `PaymentStatus recomputeStatus(Bill, List<Rentor>)`, `bool shareInputsChanged(Rentor before, Rentor after)`, `List<Bill> billsAffectedByChange(Rentor? before, Rentor after, List<Bill>)`.

Algorithms, fixtures and expected values are those in `utility_bills_server/docs/superpowers/plans/2026-11-16-property-manager-share-server.md` Task 2. Port the server's implementation and test file as-is, adjusting only imports (`package:utility_bills_manager/...`; `PaymentStatus` lives in `data/models/payment.dart`) and `test` → `flutter_test`.

- [ ] **Step 1: Copy the server test file to `test/utils/bills/property_manager_share_test.dart`, adjust imports**
- [ ] **Step 2: Run `flutter test test/utils/bills/property_manager_share_test.dart`** — Expected: FAIL, utility missing.
- [ ] **Step 3: Port the implementation to `lib/utils/bills/property_manager_share.dart`**
- [ ] **Step 4: Run the test again** — Expected: all PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/utils/bills/property_manager_share.dart test/utils/bills/property_manager_share_test.dart
git commit -m "feat: add PropertyManagerShare calculation"
```

---

### Task 3: Start date in bill eligibility and readiness

**Files:**
- Modify: `lib/services/bill_summary/bill_summary_service.dart` (`getEligibleBills` ~line 37)
- Modify: `lib/services/bill_readiness/bill_readiness_service.dart` (`relevantRentors` ~line 65)
- Test: `test/services/bill_summary/bill_summary_service_test.dart`, `test/services/bill_readiness/bill_readiness_service_test.dart`

**Interfaces:**
- Consumes: `Rentor.isActiveOn` (Task 1). `bill_selection_screen.dart` receives `getEligibleBills` output, so it needs no change.

- [ ] **Step 1: Write failing tests**

`bill_summary_service_test.dart` (extend `makeRentor` with `DateTime? startDate`):
```dart
test('getEligibleBills excludes bills due before the rentor startDate', () {
  // now 2026-11-16; rentor start 2026-11-13; electric due 2026-11-05 and 2026-11-20
  // → only the 2026-11-20 bill
});
```
`bill_readiness_service_test.dart`:
```dart
test('rentor whose startDate is after the new bill due date gets no compose notification', ...);
```

- [ ] **Step 2: Run** `flutter test test/services/bill_summary test/services/bill_readiness` — Expected: new tests FAIL.
- [ ] **Step 3: Implement** — `getEligibleBills`: `if (!rentor.isActiveOn(bill.dueDate)) return false;` alongside the exclusion check. `relevantRentors`: add `&& r.isActiveOn(newBill.dueDate)`.
- [ ] **Step 4: Run the tests again** — Expected: all PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/services test/services
git commit -m "feat: ignore bills due before a rentor's start date in summaries and readiness"
```

---

### Task 4: Computed share in payment status, summary, export; re-check on save

**Files:**
- Modify: `lib/helpers/bills/bills_helper.dart` (`_unpaidThreshold`/`_isConsideredPaid`/`_paidAmount` ~lines 381–421, inline `0.5 : 0.3` ~lines 330 and 462)
- Modify: `lib/helpers/rentors/rentors_helper.dart` (`createRentor`, `updateRentor` server-mode branches)
- Modify: `lib/screens/summary/summary_screen.dart` (`_unpaidThreshold`/`_isConsideredPaid` ~lines 96–121)
- Modify: `lib/utils/export_utils.dart` (`_thresholdNote` line 42)
- Modify: `lib/screens/rentors/add_edit_rentor_screen.dart` (`_saveRentor` ~line 433)

**Interfaces:**
- Consumes: Task 2's `PropertyManagerShare`.
- Produces: `Future<int> BillsHelper.recheckStatusesForRentorChange(Rentor? before, Rentor after)` (same contract as the server's).

- [ ] **Step 1: `BillsHelper`** — same changes as server plan Task 3 Step 3: delete `_unpaidThreshold`/`_paidAmount`, load rentors once per status-update/reversal call via `RentorsHelper().readAllRentors()`, delegate `_isConsideredPaid` to `PropertyManagerShare.isConsideredPaid`, replace both inline `0.5 : 0.3` log values with the computed share.
- [ ] **Step 2: `BillsHelper.recheckStatusesForRentorChange`** — same algorithm as server plan Task 4 Step 3.
- [ ] **Step 3: `RentorsHelper`** — in the `AppMode.server` branch only: `createRentor` → on success `recheckStatusesForRentorChange(null, rentor)`; `updateRentor` → read `before` via `dbHelper.readRentor(rentor.rentorId)` before the update, on success re-check if `before == null || PropertyManagerShare.shareInputsChanged(before, rentor)`. Re-check failures are logged, not returned as errors.
- [ ] **Step 4: `SummaryScreen`** — delete static `_unpaidThreshold`; `_isConsideredPaid(bill)` becomes `PropertyManagerShare.isConsideredPaid(bill, _rentors) || bill.status == PaymentStatus.paid`.
- [ ] **Step 5: `ExportUtils._thresholdNote`** — exact copy:
  `'Note: Bills whose unpaid amount is within the Property Manager\'s share (or within \$1.00 of it) are considered paid. Amounts in this export reflect actual values.'`
- [ ] **Step 6: `AddEditRentorScreen._saveRentor`** — after `create`/`update`, `await _billsRepository.reload();` before popping.
- [ ] **Step 7: Verify**

Run: `grep -nE "0\.30|0\.50|0\.5 : 0\.3|30%|50%" lib/helpers/bills/bills_helper.dart lib/screens/summary/summary_screen.dart lib/utils/export_utils.dart`
Expected: no output.
Run: `flutter analyze && flutter test`
Expected: no new issues; all tests PASS.

- [ ] **Step 8: Manual check (client mode against the updated server)** — with two rentors at 35% and a paid electric bill at 70% due after today, add a 15% rentor starting today: the bill shows as partial on the summary screen right after saving.
- [ ] **Step 9: Commit**

```bash
git add lib/helpers lib/screens/summary/summary_screen.dart lib/utils/export_utils.dart lib/screens/rentors/add_edit_rentor_screen.dart
git commit -m "feat: use Property Manager share for paid status and re-check on rentor save"
```

---

### Task 5: Start date field and Property Manager card

**Files:**
- Modify: `lib/screens/rentors/add_edit_rentor_screen.dart` (mirror the `_lastPaymentDate` controller/picker pattern, lines 39–117 and 428)
- Create: `lib/widgets/property_manager_card.dart`
- Modify: `lib/screens/rentors/rentor_list_screen.dart` (above the rentor `ListView.builder` ~line 409)
- Test: `test/widgets/property_manager_card_test.dart`, `test/screens/rentors/add_edit_rentor_screen_test.dart`

**Interfaces:**
- Consumes: `PropertyManagerShare.sharesAsOf` (Task 2), `Rentor.startDate` (Task 1).
- Produces: `class PropertyManagerCard extends StatelessWidget { const PropertyManagerCard({super.key, required List<Rentor> rentors, DateTime? asOf}); }`

Exact copy:
- Card title: `Property Manager`
- Card subtitle: `Covers whatever the rentors don't pay`
- Row per covered type: `'<type.name>  <share.toStringAsFixed(2)>%'` (e.g. `Gas  25.00%`), types in `BillType.values` order
- Warning (only when any share ≤ 0): `'Rentor percentages for <comma-separated type names> add up to 100% or more. Update the rentor percentages.'`
- Form field label: `Start date`; helper text: `Bills due before this date aren't split with this rentor. Leave empty if they've always been here.`

- [ ] **Step 1: Write failing widget tests**

`test/widgets/property_manager_card_test.dart`:
```dart
testWidgets('shows covered types with 2-decimal shares', (tester) async {
  // rentors A, B, C from the worked example → finds 'Gas  25.00%', 'Internet  34.00%', 'Rent  85.00%'; no 'Phone'
});
testWidgets('shows warning naming types at or over 100%', (tester) async {
  // two rentors gas 60 + 50 → finds 'Gas  -10.00%' and text containing 'Rentor percentages for Gas add up to 100% or more'
});
testWidgets('rentor with future startDate is ignored', ...);
```
`test/screens/rentors/add_edit_rentor_screen_test.dart`:
```dart
testWidgets('new rentor: start date defaults to today', ...);
testWidgets('editing rentor with null startDate shows empty field', ...);
testWidgets('clearing the start date leaves it empty', ...);
```
(If repositories make the screen hard to pump, inject nothing new — assert on the start-date field's text only and skip save.)

- [ ] **Step 2: Run** `flutter test test/widgets/property_manager_card_test.dart test/screens/rentors` — Expected: FAIL.
- [ ] **Step 3: Implement `PropertyManagerCard`** — styled like the existing rentor `Card` in `rentor_list_screen.dart`, visually distinct (e.g. outlined, lock/info icon), no tap handler; renders nothing (`SizedBox.shrink()`) when `sharesAsOf` is empty. `asOf` defaults to today.
- [ ] **Step 4: Add the card to `RentorListScreen`** above the list, passing the unfiltered rentor list from the repository (not the search/sort-filtered list); it's not part of sorting or filtering.
- [ ] **Step 5: Add the start date field to `AddEditRentorScreen`** — `_startDateController`, `DateTime? _startDate`; new rentor → today (date-only); editing → `widget.rentor!.startDate` (empty if null); date picker on tap; clear (`Icons.clear`) suffix button sets null; pass `startDate: _startDate` in `_saveRentor`.
- [ ] **Step 6: Run** `flutter test && flutter analyze` — Expected: all PASS; no new issues.
- [ ] **Step 7: Commit**

```bash
git add lib/widgets/property_manager_card.dart lib/screens/rentors test/widgets test/screens/rentors
git commit -m "feat: add rentor start date field and Property Manager card"
```

---

### Task 6: Open the PR

- [ ] **Step 1:** Add a CHANGELOG `Unreleased` entry: "Property Manager share replaces hardcoded 30%/50% thresholds; rentors have an optional start date; read-only Property Manager card on the Rentors tab."
- [ ] **Step 2:** Push `feature/property-manager-share` and open a PR against `main` referencing the spec and the merged server PR.
