# Design: Wire `latestEmailDate` Through Sync Call Chain

**Date:** 2026-04-20
**Status:** Approved

---

## Problem

`SyncOptions.latestDate` (captured from the From → To dialog) is silently discarded. None of the four screens pass it to their `_load*` methods, `EmailDataHelper` doesn't accept it, and the three `ApiService` sync methods never include it in their HTTP query params. The server already supports `latestEmailDate` on all three sync endpoints.

---

## Scope

**Changed:** 7 files — 4 screens, 1 helper, 1 API service file.

| File | Change |
|---|---|
| `lib/screens/bills/bill_list_screen.dart` | Pass `latestEmailDate: options.latestDate` to `_loadBills`; add param to `_loadBills` signature |
| `lib/screens/payments/payment_list_screen.dart` | Pass `latestEmailDate: options.latestDate` to `_loadPayments`; add param to `_loadPayments` signature |
| `lib/screens/emails/email_list_screen.dart` | Pass `latestEmailDate: options.latestDate` to `_loadEmails`; add param to `_loadEmails` signature |
| `lib/screens/summary/summary_screen.dart` | Pass `latestEmailDate: options.latestDate` to `_loadData`; add param to `_loadData` signature |
| `lib/helpers/email/email_data_helper.dart` | Add `DateTime? latestEmailDate` to `syncEmails`, `syncBillEmails`, `syncPaymentEmails`; forward to API |
| `lib/services/api/api_service.dart` | Add `DateTime? latestEmailDate` to `getSyncedBills`, `getSyncedPayments`, `getSyncedEmail`; add to query params |

---

## Data Flow

```
SyncOptionsDialog.show() → SyncOptions.latestDate
  ↓
Screen._syncXxx()           options.latestDate → _loadXxx(latestEmailDate: ...)
  ↓
Screen._loadXxx()           latestEmailDate → EmailDataHelper.syncXxxEmails(latestEmailDate: ...)
  ↓
EmailDataHelper             latestEmailDate → ApiService.getSyncedXxx(latestEmailDate: ...)
  ↓
ApiService                  latestEmailDate.toIso8601String() → query param 'latestEmailDate'
  ↓
Server /bill/list/sync, /payment/list/sync, /email/list/sync
```

Callers that don't go through the dialog (e.g. `onGoogleSignedIn`, visibility-change handlers in `summary_screen.dart`) pass `latestEmailDate: null` implicitly via the default, which is fine — the server ignores a missing `latestEmailDate`.

---

## API Serialization

Same pattern already used for `earliestEmailDate`:

```dart
if (latestEmailDate != null)
  'latestEmailDate': latestEmailDate.toIso8601String(),
```

`toIso8601String()` produces a full datetime string (e.g. `2024-04-20T00:00:00.000`), which `DateTime.tryParse` on the server handles correctly.

---

## No Logic Changes

No filtering, validation, or UI changes. This is purely parameter plumbing — add the parameter at each layer, forward it to the next, serialize at the API boundary.

---

## Testing

Unit/widget tests for `EmailDataHelper` and `ApiService` are not currently present, so no new test files. The existing full test suite (`flutter test`) must continue to pass after the changes.

For manual verification: set a From and To date in any sync dialog → trigger sync → confirm the server logs show `latestEmailDate` in the request URL.
