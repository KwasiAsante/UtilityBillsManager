# Recalculate Bill Payments — Design

**Status:** Approved
**Date:** 2026-11-16
**Repo:** utility_bills_manager (app only; no server changes)

## Why

Some bills' recorded amount paid doesn't match the payments assigned to them.
Example: the Crown Crest gas bill due 2025-01-01 ($44.43) has payments from both
rentors assigned but shows $16 paid (one rentor's 35% share) instead of $32.
Causes include payment-application bugs in older app versions and the current
apply flow (no transaction, results not checked, server trusting the app's copy
of the bill). The proper server + app fix is tracked in a separate GitHub issue.
This feature lets the user repair bills from the app now.

The user's rentors were sometimes told the wrong amounts before the app existed,
so some payments genuinely don't cover all the bills assigned to them. Those gaps
are real and should stay visible; the user fixes them by hand.

## Goals

- A **Recalculate** action per bill and a **Recalculate all bills** action on the
  Bills screen that set each bill's amount paid to what its assigned payments
  actually cover.
- A **gap warning** icon on the bill list for bills where the Property Manager is
  left covering more than their share because the assigned payments came up short.
- Manual fixes stick: recalculating never moves a bill from paid to partial/unpaid.

## Non-goals

- Fixing the payment-apply flow itself (server and app) — GitHub issue.
- Updating the server's per-bill applied-amount records (`payment_bills.appliedAmount`).
  The app has no endpoint for it, so they stay as they are (see Known limitation).
- Stopping the rentor-edit re-check from flipping manually-paid bills — GitHub issue.
- Linking payments that have no bills, or placing overpayments on bills.
- Any change to the Payments screen.

## Anti-goals

- Never credit a bill with money no rentor paid.
- Never un-pay a bill the user marked paid.

## Behaviour

### Calculation (per bill)

For a bill **X**:

1. Find every payment whose bills include X.
2. For each such payment (rentor **R**, amount **M**), walk the payment's bills in
   due-date order, oldest first (tie: billId), giving each bill
   `min(R's owed amount for that bill, money left)`. R's owed amount is
   `Rentor.calculateOwedAmount(R, bill, roundToWholeDollar: true)` — rounded to
   the whole dollar like the server's payment apply, so a recalculated bill
   matches what applying the payment records (builder's call, made in design).
   It is 0 when R excludes the type or hadn't started; such bills get nothing
   and the money carries on. Bills with status `unknown` are skipped.
   The credit from this payment to X is what reaches X.
3. X's new amount paid = the sum of credits from all its payments.
4. X's new status = `PropertyManagerShare.recomputeStatus` with the new amount,
   **except** a bill currently `paid` stays `paid`.
5. If neither amount paid nor status changes, X is not written.

Bills with no assigned payments, and `unknown`-status bills, are never touched.
Payments without a rentor are ignored (none exist today). Money left over on a
payment after all its bills stays unassigned.

Worked example (January 2025, both rentors at 35%, Ruth 50% internet):

| Bill | Shows now | After recalculate |
|---|---|---|
| Crown Crest gas, Jan 1 ($44.43) | $16 partial | $32 paid |
| Alectra electric, Jan 20 ($145.10) | $101 paid | $102 paid |
| Bell internet, Jan 23 ($188.71) | $94 paid | $94 paid |
| Enbridge gas, Jan 27 ($193.00) | $81 partial | $64 partial, gap warning |

### Recalculate actions (Bills screen)

- **Per bill:** a "Recalculate" item in each bill's menu (beside Edit / Delete).
  Recalculates that bill only (step 2 still reads the payment's other bills to see
  how far the money reached, but only X is written).
- **All bills:** "Recalculate all bills" in the app bar (wide layout) and the
  overflow menu (narrow layout), behind a confirmation dialog.
- Both show a result snackbar: how many bills changed, and how many failed to save.
  Recalculation is idempotent, so a failed run can simply be repeated.
- Both work in server mode and client mode by writing through the existing
  `BillsHelper.updateBill` (one update per changed bill).

### Gap warning

A warning icon on a bill's row when all of these hold:

- status is not `paid`;
- every rentor who owes on the bill (active on its due date, not excluding its
  type, owed amount > 0) has at least one payment assigned to it;
- the bill is not considered paid (`PropertyManagerShare.isConsideredPaid` is false).

So a bill that is only waiting on a rentor who hasn't paid yet shows no icon.
Tapping the icon (or its tooltip) explains the gap, e.g.:
"Rentors paid $64.00 of $136.00 owed. The Property Manager is covering $129.00
instead of $57.00." (paid = amount paid; owed = sum of owed amounts; covering =
bill amount − amount paid; instead of = bill amount − sum of owed amounts.)

Marking the bill paid clears the icon.

## Known limitation

The server's per-bill applied-amount records are not updated. If a payment is
later deleted or a bill removed from it, the server reverses the old recorded
amount, which can leave the bill wrong again; running Recalculate on it fixes it.
The GitHub issue covers fixing this properly.

## Approaches considered

1. **App computes; writes bills through the existing bill update (chosen).** One
   pure function decides each bill's amount and status; works in both modes; can
   honour "never un-pay"; doesn't touch payment links. Leaves applied-amount records
   stale (above).
2. **Unlink and relink each payment's bills, then re-run the server's apply.**
   Keeps applied-amount records consistent, but uses the server's allocation order
   (the order bills were picked), can't honour "never un-pay", rewrites payment
   links, and needs several calls per payment with more ways to fail halfway.
3. **New server endpoint that recalculates in a transaction.** The right long-term
   fix, deferred to the GitHub issue by the user's choice.

## Left to the builder

- Where the pure calculation lives (suggested: alongside
  `lib/utils/bills/property_manager_share.dart`) and how the Bills screen gets the
  payments (with bill ids) and rentors it needs (existing repositories).
- Exact icon, colours, dialog and snackbar wording beyond what is stated above.
