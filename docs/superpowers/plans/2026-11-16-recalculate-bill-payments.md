# Recalculate Bill Payments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-bill and all-bills "Recalculate" actions and a payment-gap warning icon to the Bills screen, so bill amounts paid can be repaired from the app.

**Architecture:** A pure calculator (`BillPaymentRecalculator`) replays each payment over its bills, oldest due date first, capped at the rentor's whole-dollar share. It produces each bill's correct amount paid and status, and detects gaps. A small runner writes only the changed bills through the existing `BillsHelper.updateBill`, which works in both server and client mode. The Bills screen wires the actions, a confirmation dialog, snackbars and a `BillGapWarning` icon.

**Tech Stack:** Flutter / Dart, `flutter_test`. No new dependencies. No server changes.

**Spec:** `docs/superpowers/specs/2026-11-16-recalculate-bill-payments-design.md`

## Global Constraints

- App repo only. No changes to `utility_bills_server`. No new packages.
- A rentor's owed amount for a bill is `Rentor.calculateOwedAmount(rentor, bill, roundToWholeDollar: true)`.
- Each payment pays its bills in due-date order, oldest first (tie: `billId` ascending), giving each `min(owed, money left)`. Bills owed 0 and bills with status `unknown` get nothing, and the money carries on.
- Recalculated amounts are rounded to cents: `(x * 100).round() / 100`.
- Status = `PropertyManagerShare.recomputeStatus` with the new amount, **except a bill whose current status is `paid` stays `paid`**.
- Never touch: bills with status `unknown`, or bills that no payment (with a known rentor) lists. Payments whose `rentorId` matches no rentor are ignored.
- Only write bills whose amount paid (compared in cents, null = 0) or status changed.
- Exact gap message: `Rentors paid $<paid> of $<owed> owed. The Property Manager is covering $<covering> instead of $<expected>.` All amounts use `toStringAsFixed(2)`.
- Follow the surrounding code style: `///` doc comments on public members, relative imports in `lib/`, package imports in `test/`.

## Review Focus

1. **Payment listing a bill its rentor doesn't owe on** (excluded type, or due before the start date). The bill gets nothing from that payment, and the money moves on to the payment's next bill. *(Task 1 test `excluded bill gets nothing and money carries on`.)*
2. **Payment listing a deleted bill, or a rentor that no longer exists.** Recalculation skips it without crashing or touching other bills. *(Task 1 tests `missing bill ids are ignored` and `payment with unknown rentor is ignored`.)*
3. **Float noise** (e.g. 33.819999). Stored amounts are cent-rounded, and a bill differing only by noise isn't rewritten. *(Task 1 tests `amounts are rounded to cents` and `float noise alone is not a change`.)*
4. **Data failing to load before a recalculation** (bills, payments or rentors reload error). Recalculation must abort with a message, never run on partial data. *(Task 4 wiring; covered in its manual check.)*
5. **One bill fails to save during "Recalculate all".** The remaining bills are still written, and the summary reports how many failed. *(Task 3 test `keeps going after a failed save`.)*

---

### Task 1: Recalculation calculator

**Files:**
- Create: `lib/utils/bills/bill_recalculation.dart`
- Test: `test/utils/bills/bill_recalculation_test.dart`

**Interfaces:**
- Consumes: `Rentor.calculateOwedAmount(Rentor, Bill, {bool roundToWholeDollar})` (`lib/data/models/rentor.dart`), `PropertyManagerShare.recomputeStatus(Bill, List<Rentor>)` (`lib/utils/bills/property_manager_share.dart`), `Payment.billIds`, `Payment.rentorId`, `Payment.amountPaid`.
- Produces:
  - `class BillRecalculation { const BillRecalculation({required this.bill, required this.amountPaid, required this.status}); final Bill bill; final double amountPaid; final PaymentStatus status; bool get changed; Bill toUpdatedBill(); }`. `bill` is the bill as it is now. `toUpdatedBill()` returns a new `Bill` with every field copied (including `id`, `billId`, `notes`) and the new `amountPaid` and `status`.
  - `class BillPaymentRecalculator` with static
    - `BillRecalculation? recalculate(Bill bill, List<Payment> payments, List<Bill> bills, List<Rentor> rentors)`: `null` when the bill must not be touched.
    - `List<BillRecalculation> recalculateAll(List<Bill> bills, List<Payment> payments, List<Rentor> rentors)`: one entry per touchable bill, changed or not.

- [ ] **Step 1: Write the failing tests**

Use the helper style of `test/utils/bills/property_manager_share_test.dart` (top-level `rentor(...)` / `bill(...)` builders, here with an explicit `billId` / `rentorId`). The January 2025 fixture:

```dart
final joseph = Rentor(rentorId: 'J', name: 'J', defaultPercentage: 35,
  billPercentages: {BillType.electric: 35, BillType.gas: 35, BillType.water: 35},
  excludedBillTypes: [BillType.internet, BillType.rent, BillType.phone,
    BillType.creditcard, BillType.personallineofcredit, BillType.other]);
final ruth = Rentor(rentorId: 'R', name: 'R', defaultPercentage: 35,
  billPercentages: {BillType.electric: 35, BillType.gas: 35,
    BillType.internet: 50, BillType.water: 35},
  excludedBillTypes: [BillType.rent, BillType.phone, BillType.creditcard,
    BillType.personallineofcredit, BillType.other]);
Bill crown() => bill(id: 'crown', type: BillType.gas, amount: 44.43,
  due: DateTime(2025, 1, 1), status: PaymentStatus.partial, amountPaid: 16);
Bill alectra() => bill(id: 'alectra', type: BillType.electric, amount: 145.10,
  due: DateTime(2025, 1, 20), status: PaymentStatus.paid, amountPaid: 101);
Bill bell() => bill(id: 'bell', type: BillType.internet, amount: 188.71,
  due: DateTime(2025, 1, 23), status: PaymentStatus.paid, amountPaid: 94);
Bill enbridge() => bill(id: 'enbridge', type: BillType.gas, amount: 193.00,
  due: DateTime(2025, 1, 27), status: PaymentStatus.partial, amountPaid: 81);
Payment pay(String rentorId, double amount, List<String> billIds) => Payment(
  rentorId: rentorId, amountPaid: amount, paymentDate: DateTime(2025, 1, 18),
  billIds: billIds);
// Both payments list bills out of due-date order on purpose.
final januaryPayments = [
  pay('J', 118, ['alectra', 'enbridge', 'crown']),
  pay('R', 174, ['enbridge', 'bell', 'alectra', 'crown']),
];
```

Tests (amounts are exact `double` equality after cent rounding):

```dart
test('January 2025 worked example', () {
  final bills = [crown(), alectra(), bell(), enbridge()];
  final byId = {for (final r in BillPaymentRecalculator.recalculateAll(
      bills, januaryPayments, [joseph, ruth])) r.bill.billId: r};
  expect(byId['crown']!.amountPaid, 32);
  expect(byId['crown']!.status, PaymentStatus.paid);
  expect(byId['crown']!.changed, isTrue);
  expect(byId['alectra']!.amountPaid, 102);
  expect(byId['alectra']!.status, PaymentStatus.paid);
  expect(byId['bell']!.amountPaid, 94);
  expect(byId['bell']!.changed, isFalse);
  expect(byId['enbridge']!.amountPaid, 64);
  expect(byId['enbridge']!.status, PaymentStatus.partial);
});

test('recalculate one bill matches recalculateAll', () {
  final bills = [crown(), alectra(), bell(), enbridge()];
  final r = BillPaymentRecalculator.recalculate(
      bills[3], januaryPayments, bills, [joseph, ruth])!;
  expect(r.amountPaid, 64);
});

test('a paid bill stays paid when its amount drops', () {
  final manual = bill(id: 'm', type: BillType.gas, amount: 44.43,
      due: DateTime(2025, 1, 1), status: PaymentStatus.paid, amountPaid: 44.43);
  final r = BillPaymentRecalculator.recalculate(
      manual, [pay('J', 16, ['m'])], [manual], [joseph, ruth])!;
  expect(r.amountPaid, 16);
  expect(r.status, PaymentStatus.paid);
});

test('unknown-status bills are not touched and consume no money', () {
  final credit = bill(id: 'credit', type: BillType.gas, amount: -89.76,
      due: DateTime(2024, 12, 1), status: PaymentStatus.unknown);
  final c = crown();
  final payments = [pay('J', 16, ['credit', 'crown'])];
  expect(BillPaymentRecalculator.recalculate(
      credit, payments, [credit, c], [joseph, ruth]), isNull);
  expect(BillPaymentRecalculator.recalculate(
      c, payments, [credit, c], [joseph, ruth])!.amountPaid, 16);
});

test('bills no payment lists are not touched', () {
  final c = crown();
  expect(BillPaymentRecalculator.recalculate(c, [], [c], [joseph, ruth]), isNull);
  expect(BillPaymentRecalculator.recalculateAll([c], [], [joseph, ruth]), isEmpty);
});

test('excluded bill gets nothing and money carries on', () {
  final b = bell(); final c = crown();
  // Joseph excludes internet, so Bell is owed 0 and skipped; the money reaches Crown Crest.
  final r = BillPaymentRecalculator.recalculateAll(
      [b, c], [pay('J', 16, ['bell', 'crown'])], [joseph, ruth]);
  final byId = {for (final x in r) x.bill.billId: x};
  expect(byId['bell']!.amountPaid, 0);
  expect(byId['crown']!.amountPaid, 16);
});

test('bill due before the rentor starts gets nothing', () {
  final late = Rentor(rentorId: 'L', name: 'L', defaultPercentage: 35,
      billPercentages: const {}, startDate: DateTime(2025, 1, 15));
  final c = crown(); final e = enbridge();
  final byId = {for (final x in BillPaymentRecalculator.recalculateAll(
      [c, e], [pay('L', 68, ['crown', 'enbridge'])], [late]))
      x.bill.billId: x};
  expect(byId['crown']!.amountPaid, 0);
  expect(byId['enbridge']!.amountPaid, 68);
});

test('missing bill ids are ignored', () {
  final c = crown();
  final r = BillPaymentRecalculator.recalculate(
      c, [pay('J', 16, ['gone', 'crown'])], [c], [joseph, ruth])!;
  expect(r.amountPaid, 16);
});

test('payment with unknown rentor is ignored', () {
  final c = crown();
  expect(BillPaymentRecalculator.recalculate(
      c, [pay('nobody', 16, ['crown'])], [c], [joseph, ruth]), isNull);
});

test('overpayment leftover stays unassigned', () {
  final c = crown();
  expect(BillPaymentRecalculator.recalculate(
      c, [pay('J', 50, ['crown'])], [c], [joseph, ruth])!.amountPaid, 16);
});

test('amounts are rounded to cents', () {
  // Shares round to $17, $83, $20; $119.07 leaves $19.07 for the newest bill.
  final g1 = bill(id: 'g1', type: BillType.gas, amount: 47.60,
      due: DateTime(2026, 11, 1), status: PaymentStatus.unpaid);
  final el = bill(id: 'el', type: BillType.electric, amount: 236.38,
      due: DateTime(2026, 11, 20), status: PaymentStatus.unpaid);
  final g2 = bill(id: 'g2', type: BillType.gas, amount: 56.24,
      due: DateTime(2026, 11, 24), status: PaymentStatus.unpaid);
  final byId = {for (final x in BillPaymentRecalculator.recalculateAll(
      [g1, el, g2], [pay('J', 119.07, ['g2', 'el', 'g1'])], [joseph, ruth]))
      x.bill.billId: x};
  expect(byId['g1']!.amountPaid, 17);
  expect(byId['el']!.amountPaid, 83);
  expect(byId['g2']!.amountPaid, 19.07);
});

test('float noise alone is not a change', () {
  final g = bill(id: 'g', type: BillType.gas, amount: 47.60,
      due: DateTime(2026, 9, 1), status: PaymentStatus.paid,
      amountPaid: 33.81999999999999);
  final r = BillPaymentRecalculator.recalculate(g,
      [pay('J', 17, ['g']), pay('R', 16.82, ['g'])], [g], [joseph, ruth])!;
  expect(r.amountPaid, 33.82);
  expect(r.changed, isFalse);
});

test('toUpdatedBill copies every field and applies the new values', () {
  final c = crown();
  final r = BillPaymentRecalculator.recalculateAll(
      [crown(), alectra(), bell(), enbridge()], januaryPayments,
      [joseph, ruth]).firstWhere((x) => x.bill.billId == 'crown');
  final u = r.toUpdatedBill();
  expect([u.billId, u.company, u.type, u.amount, u.dueDate, u.notes],
      [c.billId, c.company, c.type, c.amount, c.dueDate, c.notes]);
  expect(u.amountPaid, 32);
  expect(u.status, PaymentStatus.paid);
});
```

The `bill(...)` helper takes `id` (used as `billId`), `type`, `amount`, `due`, `status`, `amountPaid`, with `company: 'Co'` and `notes: null`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/utils/bills/bill_recalculation_test.dart`
Expected: FAIL, because `bill_recalculation.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/utils/bills/bill_recalculation.dart`**

Both public methods share one private allocation, which turns a payment into credits per bill:

```dart
// For one payment: billId -> credit. Skips payments whose rentor is unknown.
static Map<String, double> _creditsFrom(Payment payment,
    Map<String, Bill> billsById, Map<String, Rentor> rentorsById) {
  final rentor = rentorsById[payment.rentorId];
  if (rentor == null) return const {};
  final bills = (payment.billIds ?? const <String>[])
      .map((id) => billsById[id])
      .whereType<Bill>()
      .where((b) => b.status != PaymentStatus.unknown)
      .toList()
    ..sort((a, b) {
      final byDue = a.dueDate.compareTo(b.dueDate);
      return byDue != 0 ? byDue : a.billId.compareTo(b.billId);
    });
  var left = payment.amountPaid;
  final credits = <String, double>{};
  for (final b in bills) {
    final owed = Rentor.calculateOwedAmount(rentor, b, roundToWholeDollar: true);
    if (owed <= 0) continue;
    final credit = left < owed ? left : owed;
    if (credit <= 0) break;
    credits[b.billId] = (credits[b.billId] ?? 0) + credit;
    left -= credit;
  }
  return credits;
}
```

A bill is touchable when its status isn't `unknown` and at least one payment with a known rentor lists it. Its new amount is the cent-rounded sum of its credits, which can be 0 when its payments ran out before reaching it. For the status, call `PropertyManagerShare.recomputeStatus` on a copy of the bill carrying the new `amountPaid`, then keep `paid` if the current status is `paid`. `changed` compares cents (`((x ?? 0) * 100).round()`) and status. `recalculateAll` computes each payment's credits once and sums them per bill. `recalculate` does the same over only the payments that list the bill.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/utils/bills/bill_recalculation_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/utils/bills/bill_recalculation.dart test/utils/bills/bill_recalculation_test.dart
git commit -m "feat: add bill payment recalculator"
```

---

### Task 2: Gap detection and warning icon

**Files:**
- Modify: `lib/utils/bills/bill_recalculation.dart`
- Create: `lib/widgets/bill_gap_warning.dart`
- Test: `test/utils/bills/bill_recalculation_test.dart` (add a `group('gapFor')`)
- Test: `test/widgets/bill_gap_warning_test.dart`

**Interfaces:**
- Consumes: Task 1's fixtures and `BillPaymentRecalculator`, plus `PropertyManagerShare.isConsideredPaid(Bill, List<Rentor>)` and `PropertyManagerShare.paidAmount(Bill)`.
- Produces:
  - `class BillGap { final double billAmount; final double paid; final double owed; double get covering; double get expectedCovering; String get message; }`, where `covering = billAmount - paid` and `expectedCovering = billAmount - owed`.
  - `static BillGap? BillPaymentRecalculator.gapFor(Bill bill, List<Payment> payments, List<Rentor> rentors)`
  - `class BillGapWarning extends StatelessWidget { const BillGapWarning({super.key, required this.gap}); final BillGap gap; }`

`gapFor` returns a gap only when all of these hold:
- the status isn't `paid` (and isn't `unknown`);
- at least one rentor owes on the bill (`calculateOwedAmount(..., roundToWholeDollar: true) > 0`), and every such rentor has a payment whose `billIds` contains the bill;
- `isConsideredPaid` is false.

For the amounts: `paid = PropertyManagerShare.paidAmount(bill)`, and `owed` is the sum of those rentors' rounded owed amounts.

- [ ] **Step 1: Write the failing tests**

```dart
group('gapFor', () {
  test('Enbridge after recalculation has a gap with the exact message', () {
    final e = bill(id: 'enbridge', type: BillType.gas, amount: 193.00,
        due: DateTime(2025, 1, 27), status: PaymentStatus.partial, amountPaid: 64);
    final gap = BillPaymentRecalculator.gapFor(e, januaryPayments, [joseph, ruth])!;
    expect(gap.paid, 64);
    expect(gap.owed, 136);
    expect(gap.covering, 129);
    expect(gap.expectedCovering, 57);
    expect(gap.message, 'Rentors paid \$64.00 of \$136.00 owed. '
        'The Property Manager is covering \$129.00 instead of \$57.00.');
  });
  test('no gap while a rentor has not paid yet', () {
    final g = bill(id: 'g', type: BillType.gas, amount: 47.60,
        due: DateTime(2026, 11, 1), status: PaymentStatus.partial, amountPaid: 17);
    expect(BillPaymentRecalculator.gapFor(
        g, [pay('J', 17, ['g'])], [joseph, ruth]), isNull);
  });
  test('no gap on a paid bill', () {
    final e = bill(id: 'enbridge', type: BillType.gas, amount: 193.00,
        due: DateTime(2025, 1, 27), status: PaymentStatus.paid, amountPaid: 64);
    expect(BillPaymentRecalculator.gapFor(e, januaryPayments, [joseph, ruth]), isNull);
  });
  test('no gap when the shortfall is within the rounding allowance', () {
    final g = bill(id: 'g', type: BillType.gas, amount: 45.99,
        due: DateTime(2026, 1, 1), status: PaymentStatus.partial, amountPaid: 31.5);
    expect(BillPaymentRecalculator.gapFor(g,
        [pay('J', 16, ['g']), pay('R', 15.5, ['g'])], [joseph, ruth]), isNull);
  });
  test('no gap when no rentor owes on the bill', () {
    final rent = bill(id: 'rent', type: BillType.rent, amount: 1000,
        due: DateTime(2026, 1, 1), status: PaymentStatus.unpaid);
    expect(BillPaymentRecalculator.gapFor(
        rent, [pay('J', 10, ['rent'])], [joseph, ruth]), isNull);
  });
});
```

Widget test (`test/widgets/bill_gap_warning_test.dart`, in the style of `property_manager_card_test.dart`): pump `MaterialApp(home: Scaffold(body: BillGapWarning(gap: BillGap(billAmount: 193, paid: 64, owed: 136))))`.
- Expect `find.byIcon(Icons.warning_amber_rounded)`.
- Tap it, `pumpAndSettle`, and expect `find.text('Payment gap')` and `find.text(gap.message)`.
- Tap `OK` and expect the dialog to be gone.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/utils/bills/bill_recalculation_test.dart test/widgets/bill_gap_warning_test.dart`
Expected: FAIL, because `gapFor`, `BillGap` and `BillGapWarning` aren't defined.

- [ ] **Step 3: Implement `BillGap`, `gapFor` and `BillGapWarning`**

The widget is a `Tooltip(message: gap.message)` around an `InkWell` with an `Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800, semanticLabel: 'Payment gap')`. Tapping it opens an `AlertDialog` titled `Payment gap`, with `gap.message` as its content and an `OK` button that closes it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/utils/bills/bill_recalculation_test.dart test/widgets/bill_gap_warning_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/bills/bill_recalculation.dart lib/widgets/bill_gap_warning.dart test/utils/bills/bill_recalculation_test.dart test/widgets/bill_gap_warning_test.dart
git commit -m "feat: detect payment gaps and add gap warning icon"
```

---

### Task 3: Recalculation runner

**Files:**
- Create: `lib/services/bill_recalculation/bill_recalculation_runner.dart`
- Test: `test/services/bill_recalculation/bill_recalculation_runner_test.dart`

**Interfaces:**
- Consumes: `BillRecalculation.changed` / `toUpdatedBill()` (Task 1), `BillsHelper.updateBill(Bill) -> Future<Result<Bill>>`, and `Result.isSuccess` / `isError` / `errorMessage`.
- Produces:
  - `class RecalculationSummary { final int updated; final int failed; final List<String> errors; }`
  - `class BillRecalculationRunner { BillRecalculationRunner({Future<Result<Bill>> Function(Bill bill)? updateBill}); Future<RecalculationSummary> apply(List<BillRecalculation> recalculations); }`
  - When `updateBill` is null, `apply` uses `BillsHelper().updateBill`, resolved at call time so tests never construct `BillsHelper`.

- [ ] **Step 1: Write the failing tests**

```dart
test('writes only changed bills', () async {
  final written = <Bill>[];
  final runner = BillRecalculationRunner(updateBill: (b) async {
    written.add(b); return Result.success(data: b); });
  final summary = await runner.apply([changedCrown, unchangedBell]);
  expect(written.map((b) => b.billId), ['crown']);
  expect(written.single.amountPaid, 32);
  expect(summary.updated, 1);
  expect(summary.failed, 0);
});

test('keeps going after a failed save', () async {
  final runner = BillRecalculationRunner(updateBill: (b) async =>
      b.billId == 'crown' ? Result.error(errorMessage: 'boom')
                          : Result.success(data: b));
  final summary = await runner.apply([changedCrown, changedEnbridge]);
  expect(summary.updated, 1);
  expect(summary.failed, 1);
  expect(summary.errors, ['boom']);
});

test('nothing to do', () async {
  final summary = await BillRecalculationRunner(
      updateBill: (b) async => fail('should not write')).apply([unchangedBell]);
  expect([summary.updated, summary.failed], [0, 0]);
});
```

Build `changedCrown`, `changedEnbridge` and `unchangedBell` directly with the `BillRecalculation` constructor (crown $16 → $32 paid, enbridge $81 → $64 partial, bell $94 → $94 paid).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/bill_recalculation/bill_recalculation_runner_test.dart`
Expected: FAIL, because the runner doesn't exist.

- [ ] **Step 3: Implement the runner**

Write sequentially in list order and skip `!changed`. Count successes as `updated`, and count failures plus their `errorMessage` (or `'Unknown error'`). Don't stop on a failure.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/bill_recalculation/bill_recalculation_runner_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/bill_recalculation test/services/bill_recalculation
git commit -m "feat: add bill recalculation runner"
```

---

### Task 4: Bills screen wiring

**Files:**
- Modify: `lib/screens/bills/bill_list_screen.dart`
- Modify: `CHANGELOG.md` (the `[Unreleased]` → `### Added` section)
- Modify: `docs/superpowers/specs/2026-11-16-recalculate-bill-payments-design.md` (`**Status:** Draft` → `**Status:** Approved`)

**Interfaces:**
- Consumes: Tasks 1–3, `PaymentsRepository()` (`payments`, `lastError`, `reload()`, which loads `billIds`), `RentorsRepository()` (`rentors`, `lastError`, `reload()`), and `BillsRepository()`.
- Produces: no new public API.

- [ ] **Step 1: Load payments and rentors, and compute gaps**
- Add `_paymentsRepository` and `_rentorsRepository` fields, and add and remove listeners next to the existing `_billsRepository` listener in `initState` / `dispose`.
- In `_loadBills`, reload payments and rentors alongside bills.
- Keep a `Map<String, BillGap> _gaps`, rebuilt from `_allBills` with `BillPaymentRecalculator.gapFor` whenever any of the three repositories notifies.

- [ ] **Step 2: Show the gap icon**

In each bill row, replace the lone `_buildStatusBadge(bill.status)` with a `Row` of the badge. When `_gaps[bill.billId]` isn't null, follow it with `SizedBox(width: 6)` and `BillGapWarning(gap: ...)`.

- [ ] **Step 3: Add `Future<void> _recalculateBills({Bill? bill})`**

Steps in order:
1. **Confirm (all bills only).** Show an `AlertDialog`:
   - title `Recalculate All Bills`;
   - content `Set every bill's amount paid to what its assigned payments cover? Bills marked paid stay paid.`;
   - actions `Cancel` / `Recalculate`.
   Return unless confirmed.
2. **Reload fresh data.** Set a `_recalculating` flag, then reload bills, payments and rentors. If any repository's `lastError` is non-null, show the snackbar `Could not load data to recalculate: <error>` and stop.
3. **Calculate.** For one bill, use `recalculate(...)` on the reloaded copy of that bill (looked up by `billId`), otherwise `recalculateAll(...)`.
4. **Save.** `await BillRecalculationRunner().apply(...)`, then `await _billsRepository.reload()`.
5. **Snackbar:**
   - All bills, nothing changed: `All bills already match their payments.`
   - All bills, something changed: `Recalculated bills: <updated> updated.`, or `Recalculated bills: <updated> updated, <failed> failed. Run it again to retry.` when some failed.
   - One bill, `recalculate` returned null: `This bill has no payments to recalculate from.`
   - One bill, unchanged: `Bill already matches its payments.`
   - One bill, updated: `Bill updated: $<amountPaid toStringAsFixed(2)> paid, <PaymentStatusExtension.getName(status)>.`
   - One bill, failed: `Could not save bill: <error>`.
6. **Always** clear `_recalculating` (use `finally`), and check `mounted` before every `setState` and snackbar.

- [ ] **Step 4: Add the actions**
- **Wide app bar:** an `IconButton(icon: const Icon(Icons.calculate_outlined), tooltip: 'Recalculate all bills', onPressed: _loading || _recalculating ? null : () => _recalculateBills())`, placed before the delete-all button.
- **Narrow overflow menu:** after `'refresh'`, a `PopupMenuItem` with value `'recalculate_all'` showing a `ListTile` (leading `Icons.calculate_outlined`, title `Recalculate all bills`), plus a matching `case 'recalculate_all':` in `onSelected`.
- **Each bill's menu:** a `PopupMenuItem(value: 'recalculate', child: Text('Recalculate'))` between Edit and Delete, handled with `await _recalculateBills(bill: bill)`.

- [ ] **Step 5: Update the changelog and spec status**

Add under `[Unreleased]` → `### Added`:
- `- **Recalculate bill payments** — Bills screen "Recalculate" (per bill) and "Recalculate all bills" set each bill's amount paid to what its assigned payments cover (oldest bill first, capped at each rentor's share); bills marked paid stay paid.`
- `- **Payment gap warning** — bills whose rentors have all paid but came up short show a warning icon explaining how much more the Property Manager is covering.`

Set the spec's status to Approved.

- [ ] **Step 6: Verify**

Run: `flutter analyze` (expect no new issues beyond the 5 existing info-level ones) and `flutter test` (expect all to pass).

- [ ] **Step 7: Manual check (the user runs this, on a copy of the data)**

In client mode against a copy of production data:
1. **Crown Crest:** open the Bills screen. The Enbridge gas bill due 2025-01-27 shows the warning icon only after recalculating. Recalculate the Crown Crest gas bill due 2025-01-01: the snackbar reads `Bill updated: $32.00 paid, Paid.`
2. **All bills:** run "Recalculate all bills" and confirm. The snackbar gives a count. Enbridge (2025-01-27) shows $64 partial with the warning, and tapping the icon shows the exact gap message.
3. **Idempotence:** run "Recalculate all bills" again. It reads `All bills already match their payments.`
4. **Load failure:** stop the server and run "Recalculate all bills". It reads `Could not load data to recalculate: …` and no bill changes.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/bills/bill_list_screen.dart CHANGELOG.md docs/superpowers/specs/2026-11-16-recalculate-bill-payments-design.md
git commit -m "feat: add recalculate actions and gap warning to Bills screen"
```
