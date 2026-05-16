# Design: Rentor Bill Summary Messaging

**Date:** 2026-04-20
**Status:** Approved

---

## Problem

Landlords need a quick way to notify each rentor of their share of unpaid utility bills for the current month. Currently there is no in-app messaging feature — landlords must manually calculate amounts and compose messages outside the app.

---

## Scope

**Created:** 3 files — `BillSummaryService`, `BillSelectionScreen`, `MessagePreviewScreen`

**Modified:** 1 file — `AddEditRentorScreen` (add "Send Bill Summary" button)

| File | Change |
|---|---|
| `lib/services/bill_summary/bill_summary_service.dart` | New — all business logic |
| `lib/screens/bill_summary/bill_selection_screen.dart` | New — Step 1: bill selection |
| `lib/screens/bill_summary/message_preview_screen.dart` | New — Step 2: message preview/edit + share |
| `lib/screens/rentors/add_edit_rentor_screen.dart` | Modified — add "Send Bill Summary" button |

---

## Screen Flow

1. **AddEditRentorScreen** — when editing an existing rentor, a "Send Bill Summary" button appears
   - Calls `BillSummaryService.getEligibleBills(rentor)` on load to determine button state
   - Disabled (greyed out) if no eligible unpaid bills exist for the current month
   - Tapping a disabled button shows a snackbar: *"[rentor.name] is settled for this month"*
   - Tapping an enabled button navigates to `BillSelectionScreen`
   - Button is not shown when creating a new rentor

2. **BillSelectionScreen** — shows eligible bills as a checkbox list
   - Receives: `Rentor rentor`, `List<Bill> eligibleBills`
   - All bills pre-checked on load
   - Each row shows: bill type name + total amount + due date
   - "Generate Message" button disabled when no bills are checked
   - Tapping "Generate Message" calls `BillSummaryService.generateMessage(rentor, selectedBills)` and pushes `MessagePreviewScreen`

3. **MessagePreviewScreen** — shows the generated message in an editable `TextField`
   - Receives: `String initialMessage`
   - Pre-filled with the generated message; user can freely edit
   - "Share" button calls `SharePlus.instance.share(ShareParams(text: message))`
   - On platforms where the share sheet is unavailable, falls back to `Clipboard.setData(ClipboardData(text: message))` with a confirmation snackbar: *"Message copied to clipboard"*

---

## Eligibility Rules

A bill is eligible for a rentor's summary if ALL of the following are true:
1. `bill.dueDate` falls within the current calendar month and year
2. `bill.status != PaymentStatus.paid` (partial and unknown count as unpaid)
3. `bill.type` is NOT in `rentor.excludedBillTypes`

A rentor is **settled for the month** if no bills pass all three conditions.

---

## BillSummaryService

```dart
class BillSummaryService {
  /// Returns unpaid bills due this calendar month, excluding the rentor's
  /// excluded bill types.
  Future<List<Bill>> getEligibleBills(Rentor rentor) async { ... }

  /// True when [eligibleBills] is empty — rentor owes nothing this month.
  bool isSettledForMonth(List<Bill> eligibleBills) => eligibleBills.isEmpty;

  /// Generates a bill summary message for [rentor] from [selectedBills].
  String generateMessage(Rentor rentor, List<Bill> selectedBills) { ... }
}
```

`getEligibleBills` queries all bills via `BillsHelper`, filters to the current calendar month by `bill.dueDate`, excludes paid bills and excluded bill types.

### `generateMessage` Logic

1. **Greeting** — based on `DateTime.now().hour` on device:
   - Hour < 12 → "Good morning"
   - Hour 12–16 → "Good afternoon"
   - Hour ≥ 17 → "Good evening"

2. **First name** — `rentor.name.split(' ').first`

3. **Split bills** — separate `selectedBills` into `waterBills` (`BillType.water`) and `regularBills` (all others)

4. **Per-type owed amounts** — for each `BillType` in `regularBills`, sum `Rentor.calculateOwedAmount(rentor, bill)` across all bills of that type; format as `"$X.XX"`

5. **Regular due date** — average of all `regularBill.dueDate.day` values (integer average, rounded), using the current month; formatted as `"April 15th"`

6. **Water bill** — sum owed amount across all water bills using `Rentor.calculateOwedAmount`; use the water bill's own `dueDate` for formatting

7. **Assemble:**

   Regular bills only:
   ```
   "{greeting} {firstName}, {bill list} due {avgDate}."
   ```

   With water:
   ```
   "{greeting} {firstName}, {bill list} due {avgDate}. The water bill is ${owedAmount} due {waterDueDate}."
   ```

### Bill List Formatting

- 1 bill: `"the electric bill is $45.00"`
- 2 bills: `"the electric bill is $45.00 and gas bill is $30.00"`
- 3+ bills: `"the electric bill is $45.00, gas bill is $30.00 and internet bill $25.00"` (no Oxford comma before "and")

### Example Output

> "Good morning Alex, the electric bill is $45.00, gas bill is $30.00 and internet bill $25.00 due April 15th. The water bill is $20.00 due May 1st."

---

## Due Date Formatting

Format: full month name + ordinal day suffix, no year.

Ordinal suffix rules:
- 1, 21, 31 → "st"
- 2, 22 → "nd"
- 3, 23 → "rd"
- 4–20, 24–30 → "th"

Examples: `April 15th`, `May 1st`, `June 22nd`, `March 3rd`

---

## Average Due Date Calculation

Since all regular bills are filtered to the current calendar month, their due dates share the same month. The average day is:

```
avgDay = (sum of dueDate.day for all regularBills) / regularBills.length
```

Rounded to the nearest integer. Month is the current calendar month.

---

## Share Mechanism

Uses `share_plus`: `SharePlus.instance.share(ShareParams(text: message))`.

- **Mobile (iOS/Android):** system share sheet includes SMS apps
- **Web/Desktop:** system share sheet; if sharing text is unsupported, falls back to `Clipboard.setData` with a snackbar

---

## Testing

Unit tests for `BillSummaryService`:
- `getEligibleBills` excludes paid bills
- `getEligibleBills` excludes bill types in `rentor.excludedBillTypes`
- `getEligibleBills` excludes bills with `dueDate` outside the current month
- `isSettledForMonth` returns `true` for empty list, `false` for non-empty
- `generateMessage` correct format: regular bills only
- `generateMessage` correct format: water bill only
- `generateMessage` correct format: mixed regular + water
- `generateMessage` bill list join: 1 bill, 2 bills, 3+ bills
- `generateMessage` greeting: morning (hour 8), afternoon (hour 14), evening (hour 19)
- Due date ordinal suffixes: 1st, 2nd, 3rd, 11th, 12th, 13th, 21st, 22nd, 23rd
