# Design: Property Manager Share

**Date:** 2026-11-13
**Status:** Pending approval
**Repos:** `utility_bills_manager` (Flutter app) and `utility_bills_server` (Dart server)

---

## Why

The app treats the last 30% of electric/gas/water bills and the last 50% of internet bills as "already paid". That remainder is the owner's (the app creator's) share — an invisible property manager who pays whatever the tracked rentors don't.

A new rentor is joining who will split the owner's share (15% / 15% for utilities; internet changes too). The hardcoded 30/50 is now wrong, and will be wrong again every time the rentor mix changes.

**Fix:** derive the owner's share — the **Property Manager share** — from the rentors themselves, per bill, instead of hardcoding it.

## Goals

- Property Manager share for a bill = `100% − Σ (each active rentor's percentage for that bill type)`.
- Only rentors active for that bill count, so adding a rentor affects bills due on/after their start date and never re-judges older bills.
- The "considered paid" check (app summary screen, app and server payment-status updates, payment reversal) uses the Property Manager share instead of 30/50.
- The Property Manager is visible in the app as a read-only entry so the owner can see the current split.

## Non-goals

- No stored Property Manager row in either database. It is computed, never persisted, never synced.
- The Property Manager never receives payments, bill summary messages, notifications, or email payment matching.
- No rentor end date / move-out in this change (start date is designed so an end date can be added later the same way).
- No dated history of percentage edits. Editing an existing rentor's percentage affects all of that rentor's bills that aren't already settled.

## Anti-goals

- Bills already marked `paid` must not flip back to partial/unpaid because a rentor was added or edited — **except** bills due on/after a newly saved rentor's `startDate` (see "Re-check on rentor save").
- No rounding of the computed share anywhere — use the exact value.
- No blocking validation on rentor save when totals exceed 100%.

---

## Rules (as decided)

### Which rentors count for a bill

A rentor counts toward a bill when **`rentor.startDate` is null or `rentor.startDate ≤ bill.dueDate`** (compare by date, ignoring time).

- `startDate` is a new nullable rentor field. Null means "has always been here" — all existing rentors are migrated as null.
- New rentors default `startDate` to today in the add-rentor form; the user can change it (including to a future move-in date).

### A rentor's percentage for a bill type

Same lookup the app already uses in `Rentor.calculateOwedAmount`:

1. If the type is in `excludedBillTypes` → 0.
2. Else if `billPercentages[type]` exists → that value.
3. Else → `defaultPercentage`.

### Which bill types the Property Manager covers

Any bill type that **at least one counting rentor has not excluded**. If every counting rentor excludes a type (or there are no counting rentors), the Property Manager does not cover it → no "considered paid" threshold for that type (same as rent/phone/credit card today).

### Property Manager share

`pmShare = 100 − Σ percentage(rentor, type)` over counting rentors, exact (no rounding).

- If `pmShare ≤ 0`, the threshold is treated as **0%** — the bill must be paid in full (the existing $1.00 tolerance still applies). The app shows a warning on the Property Manager entry (see UI) so the owner knows a rentor's percentage needs fixing.

Worked example (all rentors counting, no bill-specific overrides beyond those listed):

| Rentor | Excluded | Gas | Electric | Internet |
|---|---|---|---|---|
| A | internet, rent, phone, creditcard, personallineofcredit | 30 | 30 | — |
| B | rent, phone, creditcard, personallineofcredit | 30 | 30 | 33 |
| C | phone, creditcard, personallineofcredit | 15 | 15 | 33 |
| **Property Manager** | | **25** | **25** | **34** |

Rent is covered too (C hasn't excluded it): `100 − C's rent percentage`.

### "Considered paid"

Unchanged in shape, only the fraction changes:

```
threshold   = pmShareForBill(bill, rentors) / 100   // null if PM doesn't cover the type
considered  = threshold != null &&
              (unpaid <= 0 || unpaid <= bill.amount * max(threshold, 0) + 1.00)
```

The summary screen keeps its existing `|| bill.status == PaymentStatus.paid` short-circuit, which is what keeps already-settled bills settled.

### Rentor's own owed amount respects start date (confirmed by owner)

A rentor owes **0** on bills due before their `startDate`. Apply this in `Rentor.calculateOwedAmount` and `calculateOwedBreakdown` (app) and the server equivalents. Consequences (all intended):

- Payments from that rentor are never applied to pre-start bills.
- Pre-start bills don't appear for that rentor in `BillSummaryService.getEligibleBills`, `bill_selection_screen`, or `BillReadinessService` compose notifications (filtered out, not shown as $0).

### Re-check on rentor save (confirmed by owner)

Bills due on/after a new rentor's start date may already be marked `paid` under the old share (e.g. the current rentors paid 70% → paid at a 30% threshold). Without a re-check, the new rentor would never be asked for their part.

When a rentor is **created**, or an existing rentor's **`startDate`, percentages, or exclusions change**, re-evaluate every bill with `dueDate ≥ that rentor's startDate` (all bills if `startDate` is null) whose type that rentor isn't excluded from:

- Recompute "considered paid" with the new rentor list.
- A `paid` bill that no longer qualifies becomes `partial` (or `unpaid` if `amountPaid` is 0). An unpaid/partial bill that now qualifies becomes `paid`.
- `amountPaid` is never modified — only `status`.
- Bills due before the rentor's `startDate` are never touched.

This runs where the authoritative status lives: on the server in client mode (after rentor create/update), and in the app's `BillsHelper` in server mode.

### Server owed amount aligned with the app (confirmed by owner)

The server's `Rentor.calculateOwedAmount` currently ignores `excludedBillTypes` and `defaultPercentage` (falls back to 0). Change it to the app's lookup — excluded → 0, else bill-specific %, else default % — plus the start-date rule. **Keep** its existing whole-dollar rounding of the owed amount (that's the payment cap, separate from the no-rounding rule for the Property Manager percentage).

### Note on current data

With today's rentors (35/35/35 utilities, 50 internet) the calculation yields exactly 30/50, so nothing changes until a rentor is added or edited. One rentor doesn't exclude `other`, so `other` bills become covered (65%) under these rules. Accepted; the owner can exclude `other` on that rentor if it isn't wanted.

---

## Approaches considered

| | Approach | Trade-off | Decision |
|---|---|---|---|
| A | **Rentor start date**; PM share computed per bill from rentors active on its due date | Handles future rentors and future move-in dates; one new column. Percentage edits to existing rentors aren't dated, so they affect unsettled older bills. | **Chosen** |
| B | Snapshot PM share onto each bill at creation | Freezes history fully, but a bill created before a rentor is added never picks them up even if due after; needs re-snapshot logic for unsettled bills. | Rejected — messier |
| — | Persist the Property Manager as a real rentor row | Needs special-casing in payment parsing, messages, notifications, sync, edit/delete guards. | Rejected — computed is simpler |

Due date is the date compared against `startDate` (bills have no statement/issue date). A bill for October usage due November 20 counts a rentor who started November 13 — accepted by the owner.

---

## Changes

### Shared calculation (both repos)

Add a single pure function (per repo — the repos don't share code) e.g.:

```dart
/// Returns the Property Manager's percentage (0–100, unrounded, may be ≤ 0)
/// for [bill], or null if no counting rentor covers [bill.type].
double? propertyManagerShare(Bill bill, List<Rentor> rentors);
```

plus a variant keyed by `(BillType, DateTime asOf)` for the UI. Placement is the builder's call (a new `lib/utils/property_manager.dart` or a static on a small `PropertyManager` class in `lib/data/models/`).

### App — `utility_bills_manager`

| File | Change |
|---|---|
| `lib/data/models/rentor.dart` | Add `DateTime? startDate`; `fromJson`, `rentorFromJson` (`r_startDate`), `toJson` (date-only `yyyy-MM-dd`, like `lastPaymentDate`), `toDbJson`. Owed-amount helpers return 0 for bills due before `startDate`. |
| `lib/helpers/database/database_helper.dart` | Bump version; `ALTER TABLE rentors ADD COLUMN startDate TEXT` (null for existing rows). Update any `r_` JOIN select lists to include `startDate AS r_startDate`. |
| `lib/helpers/bills/bills_helper.dart` | Replace `_unpaidThreshold` with the shared calculation. `_isConsideredPaid` needs the rentor list — load via `RentorsHelper`/repository. Replace inline `0.5 : 0.3` in the two log lines with the computed share. Add the re-check routine (used in server mode). |
| `lib/helpers/rentors/rentors_helper.dart` | In server mode, trigger the re-check after rentor create/update when start date, percentages, or exclusions change. |
| `lib/services/bill_summary/bill_summary_service.dart`, `lib/services/bill_readiness/bill_readiness_service.dart`, `lib/screens/bill_summary/bill_selection_screen.dart` | Exclude bills due before the rentor's `startDate`. |
| `lib/screens/summary/summary_screen.dart` | Replace static `_unpaidThreshold` with the shared calculation using the already-loaded rentors from `_rentorsRepo`. |
| `lib/utils/export_utils.dart` | Replace the hardcoded 30%/50% note with generic wording, e.g. "Bills whose unpaid amount is within the Property Manager's share (or within $1.00 of it) are considered paid. Amounts in this export reflect actual values." |
| `lib/screens/rentors/add_edit_rentor_screen.dart` | Add a "Start date" date picker; defaults to today for new rentors, shows stored value (or "Always" / empty for null) when editing. Clearable. |
| `lib/screens/rentors/rentor_list_screen.dart` | Show a read-only **Property Manager** card (pinned top or bottom, not sortable, no tap-to-edit, no delete) listing each covered bill type and its current share (as of today, exact value formatted to 2 decimals for display only). If any share ≤ 0, show a warning line naming the bill type(s). |

### Server — `utility_bills_server`

| File | Change |
|---|---|
| `lib/data/models/rentor.dart` | Same `startDate` field + JSON/DB mapping + owed-amount start-date rule. |
| `lib/helpers/database/database_helper.dart` | Migration adding `rentors.startDate TEXT`; update `r_` JOIN selects. |
| `lib/helpers/bills/bills_helper.dart` | Replace `_unpaidThreshold` and the inline `0.5 : 0.3` with the shared calculation (load rentors). Add the re-check routine. |
| `lib/helpers/rentors/rentors_helper.dart` | Trigger the re-check after rentor create/update when start date, percentages, or exclusions change. |
| `lib/data/models/rentor.dart` (owed amount) | Align `calculateOwedAmount` with the app's lookup (exclusions, default %); keep whole-dollar rounding. |
| `lib/utils/bills/monthly_bill_summary.dart`, `lib/utils/payments/payments_parser.dart` | Review for owed-amount usage; they should pick up the start-date rule via the model. |
| Postman collection (`postman/collections/...`) | Add `startDate` to Create/Update Rentor request bodies. |

### Compatibility / rollout

- The server must accept and return `startDate` before the app relies on it; otherwise in client mode the app's `startDate` is dropped on round-trip. **Ship the server first**, then the app.
- Old app → new server: field is ignored/null → rentor treated as "always here". Safe.
- Server PR #41 (`feature/monthly-bill-summary-reminder`) uses DB v18. The server work branches from `main` after #41 is merged, and its migration is numbered after #41's.

---

## Testing

- Unit tests for the shared calculation: the worked example above; bill-specific override vs default; excluded types; type excluded by all → null; no rentors → null; sum > 100 → ≤ 0 share → threshold 0; rentor with future `startDate` doesn't count; rentor with `startDate == dueDate` counts; null `startDate` counts.
- `_isConsideredPaid` / payment-status: bill due before new rentor's start keeps old threshold; bill due after uses new one; reversal path recomputes with the same rule.
- Rentor JSON/DB round-trip with and without `startDate`; DB migration from previous version leaves existing rentors with null.
- Summary screen: a bill already `paid` and due before the new rentor's start stays paid after adding them.
- Re-check: adding a rentor reopens a `paid` bill due on/after their start that no longer meets the new share; leaves pre-start bills untouched; never changes `amountPaid`.
- Server owed amount: excluded type → 0; no bill-specific % → default %; pre-start bill → 0.

## Left to the builder

- Exact placement/name of the shared function and the UI variant.
- Where the Property Manager card sits in the list and its styling (follow existing rentor card style, visually distinguished as read-only).
- How `bills_helper` obtains rentors (repository vs helper read) in each repo.
- DB version numbers.
