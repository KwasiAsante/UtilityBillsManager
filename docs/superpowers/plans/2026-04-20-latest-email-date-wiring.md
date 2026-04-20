# Wire `latestEmailDate` Through Sync Call Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thread `SyncOptions.latestDate` from the sync dialog all the way to the three server sync endpoints as the `latestEmailDate` query parameter.

**Architecture:** Pure parameter plumbing — add `DateTime? latestEmailDate` at every layer in the call chain (screens → EmailDataHelper → ApiService), then serialize to ISO 8601 in the existing query-param builder pattern. No logic changes, no new files.

**Tech Stack:** Flutter, Dart, `http` package (already in use)

---

## File Map

| File | Change |
|---|---|
| `lib/services/api/api_service.dart` | Add `latestEmailDate` param + query entry to `getSyncedBills`, `getSyncedPayments`, `getSyncedEmail` |
| `lib/helpers/email/email_data_helper.dart` | Add `latestEmailDate` param to `syncEmails`, `syncBillEmails`, `syncPaymentEmails`; forward to API calls |
| `lib/screens/bills/bill_list_screen.dart` | Add `latestEmailDate` to `_loadBills` signature; pass `options.latestDate` from dialog |
| `lib/screens/payments/payment_list_screen.dart` | Add `latestEmailDate` to `_loadPayments` signature; pass `options.latestDate` from dialog |
| `lib/screens/emails/email_list_screen.dart` | Add `latestEmailDate` to `_loadEmails` signature; pass `options.latestDate` from dialog |
| `lib/screens/summary/summary_screen.dart` | Add `latestEmailDate` to `_loadData` signature; pass `options.latestDate` from dialog |

---

### Task 1: Create the feature branch

- [ ] **Step 1: Create and check out the branch**

```bash
git checkout -b feat/latest-email-date-wiring
```

- [ ] **Step 2: Verify**

```bash
git branch --show-current
```
Expected: `feat/latest-email-date-wiring`

---

### Task 2: Update `api_service.dart`

**Files:**
- Modify: `lib/services/api/api_service.dart`

- [ ] **Step 1: Read the file**

Read `lib/services/api/api_service.dart` in full before editing.

- [ ] **Step 2: Add `latestEmailDate` to `getSyncedBills`**

Find this block:
```dart
  Future<List<Bill>?> getSyncedBills({
    int? maxEmails,
    DateTime? earliestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
      };
```

Replace with:
```dart
  Future<List<Bill>?> getSyncedBills({
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
        if (latestEmailDate != null)
          'latestEmailDate': latestEmailDate.toIso8601String(),
      };
```

- [ ] **Step 3: Add `latestEmailDate` to `getSyncedPayments`**

Find this block:
```dart
  Future<List<Payment>?> getSyncedPayments({
    Map<String, bool>? include,
    List<String>? ids,
    int? maxEmails,
    DateTime? earliestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
        if (ids != null) 'payment_ids': ids.join(','),
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
      };
```

Replace with:
```dart
  Future<List<Payment>?> getSyncedPayments({
    Map<String, bool>? include,
    List<String>? ids,
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
        if (ids != null) 'payment_ids': ids.join(','),
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
        if (latestEmailDate != null)
          'latestEmailDate': latestEmailDate.toIso8601String(),
      };
```

- [ ] **Step 4: Add `latestEmailDate` to `getSyncedEmail`**

Find this block:
```dart
  Future<Map<String, dynamic>?> getSyncedEmail({
    int? maxEmails,
    DateTime? earliestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
      };
```

Replace with:
```dart
  Future<Map<String, dynamic>?> getSyncedEmail({
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
        if (latestEmailDate != null)
          'latestEmailDate': latestEmailDate.toIso8601String(),
      };
```

- [ ] **Step 5: Verify**

```bash
flutter analyze lib/services/api/api_service.dart
```
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/services/api/api_service.dart
git commit -m "feat: add latestEmailDate query param to sync API methods"
```

---

### Task 3: Update `email_data_helper.dart`

**Files:**
- Modify: `lib/helpers/email/email_data_helper.dart`

- [ ] **Step 1: Read the file**

Read `lib/helpers/email/email_data_helper.dart` in full before editing.

- [ ] **Step 2: Add `latestEmailDate` to `syncEmails` signature**

Find:
```dart
  Future<Result<Map<String, dynamic>>> syncEmails({
    int? maxEmails,
    DateTime? earliestEmailDate,
  }) async {
```

Replace with:
```dart
  Future<Result<Map<String, dynamic>>> syncEmails({
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
```

- [ ] **Step 3: Pass `latestEmailDate` to `getSyncedEmail` inside `syncEmails`**

Find the call to `getSyncedEmail` inside `syncEmails` (in the server-mode branch). It looks like:
```dart
        map = await ApiService.emails().getSyncedEmail(
          maxEmails: maxEmails,
          earliestEmailDate: earliestEmailDate,
        );
```

Replace with:
```dart
        map = await ApiService.emails().getSyncedEmail(
          maxEmails: maxEmails,
          earliestEmailDate: earliestEmailDate,
          latestEmailDate: latestEmailDate,
        );
```

- [ ] **Step 4: Add `latestEmailDate` to `syncBillEmails` signature**

Find:
```dart
  Future<void> syncBillEmails({
    int? maxEmails,
    DateTime? earliestEmailDate,
  }) async {
```

Replace with:
```dart
  Future<void> syncBillEmails({
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
```

- [ ] **Step 5: Pass `latestEmailDate` to `getSyncedBills` inside `syncBillEmails`**

Find the call to `getSyncedBills` inside `syncBillEmails` (server-mode branch). It looks like:
```dart
      final bills = await ApiService.bills().getSyncedBills(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
      );
```

Replace with:
```dart
      final bills = await ApiService.bills().getSyncedBills(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
        latestEmailDate: latestEmailDate,
      );
```

- [ ] **Step 6: Add `latestEmailDate` to `syncPaymentEmails` signature**

Find:
```dart
  Future<void> syncPaymentEmails({
    int? maxEmails,
    DateTime? earliestEmailDate,
  }) async {
```

Replace with:
```dart
  Future<void> syncPaymentEmails({
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
```

- [ ] **Step 7: Pass `latestEmailDate` to `getSyncedPayments` inside `syncPaymentEmails`**

Find the call to `getSyncedPayments` inside `syncPaymentEmails` (server-mode branch). It looks like:
```dart
      final payments = await ApiService.payments().getSyncedPayments(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
      );
```

Replace with:
```dart
      final payments = await ApiService.payments().getSyncedPayments(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
        latestEmailDate: latestEmailDate,
      );
```

- [ ] **Step 8: Verify**

```bash
flutter analyze lib/helpers/email/email_data_helper.dart
```
Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/helpers/email/email_data_helper.dart
git commit -m "feat: add latestEmailDate param to EmailDataHelper sync methods"
```

---

### Task 4: Update the four screen files

**Files:**
- Modify: `lib/screens/bills/bill_list_screen.dart`
- Modify: `lib/screens/payments/payment_list_screen.dart`
- Modify: `lib/screens/emails/email_list_screen.dart`
- Modify: `lib/screens/summary/summary_screen.dart`

Each screen has the same two-part change:
1. Add `latestEmailDate: options.latestDate` to the `_load*` call in the sync method
2. Add `DateTime? latestEmailDate` to the `_load*` signature and forward it to the helper

#### `bill_list_screen.dart`

- [ ] **Step 1: Read `lib/screens/bills/bill_list_screen.dart`**

- [ ] **Step 2: Add `latestEmailDate` to the `_loadBills` call in the sync method**

Find (the call inside `_syncBills` or equivalent):
```dart
    await _loadBills(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      maxEmails: options.maxEmails,
    );
```

Replace with:
```dart
    await _loadBills(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      latestEmailDate: options.latestDate,
      maxEmails: options.maxEmails,
    );
```

- [ ] **Step 3: Add `latestEmailDate` to the `_loadBills` signature**

Find:
```dart
  Future<void> _loadBills({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    int? maxEmails,
  }) async {
```

Replace with:
```dart
  Future<void> _loadBills({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
    int? maxEmails,
  }) async {
```

- [ ] **Step 4: Forward `latestEmailDate` to `syncBillEmails` inside `_loadBills`**

Find the call to `syncBillEmails` inside `_loadBills`. It looks like:
```dart
      await _emailDataHelper.syncBillEmails(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
      );
```

Replace with:
```dart
      await _emailDataHelper.syncBillEmails(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
        latestEmailDate: latestEmailDate,
      );
```

#### `payment_list_screen.dart`

- [ ] **Step 5: Read `lib/screens/payments/payment_list_screen.dart`**

- [ ] **Step 6: Add `latestEmailDate` to the `_loadPayments` call in the sync method**

Find:
```dart
    await _loadPayments(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      maxEmails: options.maxEmails,
    );
```

Replace with:
```dart
    await _loadPayments(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      latestEmailDate: options.latestDate,
      maxEmails: options.maxEmails,
    );
```

- [ ] **Step 7: Add `latestEmailDate` to the `_loadPayments` signature**

Find:
```dart
  Future<void> _loadPayments({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    int? maxEmails,
  }) async {
```

Replace with:
```dart
  Future<void> _loadPayments({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
    int? maxEmails,
  }) async {
```

- [ ] **Step 8: Forward `latestEmailDate` to `syncPaymentEmails` inside `_loadPayments`**

Find the call to `syncPaymentEmails` inside `_loadPayments`. It looks like:
```dart
      await _emailDataHelper.syncPaymentEmails(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
      );
```

Replace with:
```dart
      await _emailDataHelper.syncPaymentEmails(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
        latestEmailDate: latestEmailDate,
      );
```

#### `email_list_screen.dart`

- [ ] **Step 9: Read `lib/screens/emails/email_list_screen.dart`**

- [ ] **Step 10: Add `latestEmailDate` to the `_loadEmails` call in the sync method**

Find:
```dart
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      maxEmails: options.maxEmails,
```

Replace with:
```dart
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      latestEmailDate: options.latestDate,
      maxEmails: options.maxEmails,
```

- [ ] **Step 11: Add `latestEmailDate` to the `_loadEmails` signature**

Find:
```dart
  Future<void> _loadEmails({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    int? maxEmails,
  }) async {
```

Replace with:
```dart
  Future<void> _loadEmails({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
    int? maxEmails,
  }) async {
```

- [ ] **Step 12: Forward `latestEmailDate` to `syncEmails` inside `_loadEmails`**

Find the call to `syncEmails` inside `_loadEmails`. It looks like:
```dart
      await _emailDataHelper.syncEmails(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
      );
```

Replace with:
```dart
      await _emailDataHelper.syncEmails(
        maxEmails: maxEmails,
        earliestEmailDate: earliestEmailDate,
        latestEmailDate: latestEmailDate,
      );
```

#### `summary_screen.dart`

- [ ] **Step 13: Read `lib/screens/summary/summary_screen.dart`**

- [ ] **Step 14: Add `latestEmailDate` to the `_loadData` call in `_syncData`**

Find (inside `_syncData`):
```dart
    await _loadData(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      maxEmails: options.maxEmails,
    );
```

Replace with:
```dart
    await _loadData(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      latestEmailDate: options.latestDate,
      maxEmails: options.maxEmails,
    );
```

- [ ] **Step 15: Add `latestEmailDate` to the `_loadData` signature**

Find:
```dart
  Future<void> _loadData({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    int? maxEmails,
  }) async {
```

Replace with:
```dart
  Future<void> _loadData({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
    int? maxEmails,
  }) async {
```

- [ ] **Step 16: Forward `latestEmailDate` to `syncEmails` inside `_loadData`**

Find the call to `syncEmails` inside `_loadData`:
```dart
      await _emailDataHelper.syncEmails(
        earliestEmailDate: earliestEmailDate,
        maxEmails: maxEmails,
      );
```

Replace with:
```dart
      await _emailDataHelper.syncEmails(
        earliestEmailDate: earliestEmailDate,
        latestEmailDate: latestEmailDate,
        maxEmails: maxEmails,
      );
```

- [ ] **Step 17: Verify all four screens**

```bash
flutter analyze lib/screens/bills/bill_list_screen.dart \
               lib/screens/payments/payment_list_screen.dart \
               lib/screens/emails/email_list_screen.dart \
               lib/screens/summary/summary_screen.dart
```
Expected: no errors.

- [ ] **Step 18: Commit**

```bash
git add lib/screens/bills/bill_list_screen.dart \
        lib/screens/payments/payment_list_screen.dart \
        lib/screens/emails/email_list_screen.dart \
        lib/screens/summary/summary_screen.dart
git commit -m "feat: pass latestEmailDate from SyncOptions through screen load methods"
```

---

### Task 5: Full test suite and PR

- [ ] **Step 1: Run the full test suite**

```bash
flutter test
```
Expected: All tests pass (no regressions).

- [ ] **Step 2: Push the branch**

```bash
git push -u origin feat/latest-email-date-wiring
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create \
  --title "feat: wire latestEmailDate through sync call chain to server" \
  --body "$(cat <<'EOF'
## Summary
- Adds `DateTime? latestEmailDate` parameter to `getSyncedBills`, `getSyncedPayments`, `getSyncedEmail` in `ApiService` — serialized as `latestEmailDate=<ISO8601>` query param
- Adds `DateTime? latestEmailDate` to `syncEmails`, `syncBillEmails`, `syncPaymentEmails` in `EmailDataHelper` — forwarded to the API methods above
- Updates `_loadBills`, `_loadPayments`, `_loadEmails`, `_loadData` in all 4 screen files — adds the param and passes it to the helper
- Updates the dialog call sites in all 4 screens to pass `options.latestDate`
- Non-dialog callers (onGoogleSignedIn, visibility handlers) use the default `null` — no behaviour change

## Test plan
- [ ] Run `flutter test` — all tests pass
- [ ] Open the app, tap Sync on the Bills screen, set a From and To date, tap Sync — server logs show `latestEmailDate` in the request URL
- [ ] Sync without a To date — `latestEmailDate` absent from request URL (server fetches up to today)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
