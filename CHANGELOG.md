# Changelog

All notable changes to this project are documented here.

---

## [Unreleased]

### Changed
- `AppConfig`: default `APP_MODE` changed from `server` to `client`; fallback in `mode` getter now also returns `AppMode.client`.
- `AddEditPaymentScreen`: switched from `PaymentsHelper` to `PaymentsRepository` for create/update; fixed bill due-date display to use `DateFormat('yyyy-MM-dd')` instead of raw `DateTime.toString()`.
- `AddEditRentorScreen`: removed unused `_calculateAmountOwed()` method and its "Amount Owed" UI field; removed unused `BillsHelper` and `Payment` imports.
- `ApiService` (payments): `createPayment` and `updatePayment` now serialize via `toJson(include: {'bill': true, 'rentor': true})` so bill IDs and rentor ID are sent to the API; `getPayments` now maps `billList` from the response into full `Bill` objects via `Payment.fromJson`.
- `ApiService` (emails): `getEmail` forwards a `query_by_email_id` query parameter to the API.

### Added
- `Payment.toJson`: optional `include` map parameter — passing `{'bill': true}` appends `billIds` and `{'rentor': true}` ensures `rentorId` is present in the serialized output.
- `DatabaseHelper.readEmail` / `EmailDataHelper.readEmail`: new `queryByEmailId` flag to query email records by `emailId` (IMAP message ID) instead of the default `emailDataId` primary key.
- `SummaryScreen`: `fetchPaymentEmails()` is now called alongside `fetchBillEmails()` during Gmail sync so payment-related emails are also fetched.

### Fixed
- `SummaryScreen._isConsideredPaid`: bills with `PaymentStatus.paid` are now always treated as paid regardless of threshold calculation.

---

## [1.0.0] — Current

### Added — Logging
- Introduced `AppLogger` utility with structured log levels, replacing verbose inline logging across `api_service`, email helpers, parsers, and related utilities. (`refactor: introduce AppLogger utility`)

### Changed — Imports & Payment Threshold Logic
- Migrated all package-level imports to relative imports across models, helpers, screens, services, and utils.
- Extracted `_isConsideredPaid` and `_unpaidThreshold` helpers in `BillsHelper` to centralise bill-payment threshold logic and remove inline duplication. (`refactor: migrate to relative imports and extract payment threshold logic`)

### Fixed — Dropdown & Dependencies
- Updated `DropdownButtonFormField` to use `initialValue` instead of a manual controller.
- Cleaned up `pubspec.yaml` dependency versions. (`fix: update DropdownButtonFormField to use initialValue`)

### Added — Documentation
- Added `///` doc comments and inline comments to every class, method, factory, getter, extension, and enum in `lib/`. (`docs: add /// doc comments`)

### Fixed — Web Compatibility for Export
- Removed all usage of `dart:io File` and `path_provider getTemporaryDirectory()`, which are unsupported on Flutter Web.
- CSV and PDF exports now use `XFile.fromData()` to hold content in memory, working across all platforms. (`fix: replace dart:io/path_provider with XFile.fromData for web compatibility`)

### Added — Summary Screen Overhaul
- Migrated `SummaryScreen` from direct helpers to repository counterparts (`BillsRepository`, `PaymentsRepository`, `RentorsRepository`).
- Added Google sign-in integration: sign-in button, warning banner when not signed in, and sync via `SyncOptionsDialog`.
- Added `isVisible` prop so the Google sign-in subscription is only active when the tab is visible.
- Repository listeners feed a single debounced `_onDataChanged` via `addPostFrameCallback`, coalescing concurrent `notifyListeners` calls into one `setState`.
- "Considered paid" threshold logic: electric/gas/water bills with ≤ 30% unpaid (or within $1 of the threshold) and internet ≤ 50% are treated as fully paid in the summary display.
- Visibility toggle (eye icon) to show/hide actual unpaid amounts when threshold suppression is active.
- Rentor payment contributions shown per bill row (paid-by names) and aggregated per month/type section; bill payment index built once per data load for O(1) lookups.
- Bills sorted descending by due date within each month card.
- CSV and PDF exports include per-bill rentor contributions and a threshold note.
- Added `deleteAll()` method to `PaymentsRepository` (was missing). (`feat: overhaul SummaryScreen`)

### Fixed — Date Fields & Model Bugs
- Migrated `dueDate` (Bill), `paymentDate` (Payment), and `lastPaymentDate` (Rentor) from `String`/`String?` to `DateTime`/`DateTime?` throughout models, factory constructors, and all call sites.
- Fixed `Bill.toJson`, `Payment.toJson`, and `Rentor.toJson` to serialize dates as ISO strings.
- Replaced broken rentor setter on `Payment` with `addRentor()` method.
- Fixed `Rentor.getAmountOwed` fold accumulator (was discarding total, returning only the last bill's amount).
- Fixed `Rentor.updateLastPaymentDate` sort direction so `payments.first` is the most recent date.
- Fixed `AddEditBillScreen` AppBar title (was always "Add Bill").
- Fixed `SummaryScreen` status filter case mismatch; added `mounted` checks.
- Extracted `ComparableUtils.compareNullable` to remove duplication across sort comparators.
- Added bounds checks in `BillsParser.getAmountFromNextIndex`/`getDateFromNextIndex` to prevent `RangeError` on last-line keywords. (`fix: migrate date fields to DateTime and fix serialization/model bugs`)

### Added — Email Screens
- Replaced `EmailListScreen` stub with a full implementation: Gmail sync, search, filter (All/Processed/Unprocessed), sort, individual/bulk delete with confirmation.
- Added `EditEmailDataScreen` to view email body, toggle processed state, and update linked bill/payment.
- Added `onTap` navigation on list cards in `BillListScreen`, `RentorListScreen`, and `PaymentListScreen`.
- Added `deleteEmailDataByEmailDataId` threaded through `DatabaseHelper`, `EmailDataHelper`, and `EmailDataRepository`. (`Implement EmailListScreen, EditEmailDataScreen`)

### Added — Payment Amount Tracking & Repository Layer
- Added `amountPaid` field to `Bill` and `excludedBillTypes` to `Rentor`; persisted across JSON/DB paths.
- Added `payment_bills` schema columns `applied` and `appliedAmount` to record how much of a payment was applied per bill (DB migrations v11 → v14).
- `BillsHelper`: added `markPaymentBillApplied`, `reversePaymentStatusForBills`, and updated `updatePaymentStatuses` to use stored `appliedAmount`.
- `PaymentsHelper.deletePayment` and `deleteAllPayments`: reverse bill statuses when payments are deleted.
- Extracted `BillsRepository`, `PaymentsRepository`, `RentorsRepository`, `EmailDataRepository` as `ChangeNotifier` singletons to decouple screens from helpers. (`Introduces infrastructure for accurate payment tracking`)

### Changed — Payment & Rentor Handling
- Refactored payment status updates and last-payment-date logic across `PaymentsHelper` and `RentorsHelper`. (`Refactor payment and rentor handling`)

### Added — Rentor & Bill Assignment to Payments
- Payments can now be associated with specific rentors and bills at creation/edit time. (`Added rentor and bills assignment to payment`)

### Added — Rentor & Payment Screens
- Major updates to rentor and payment screens: list views, add/edit flows, status badges, sorting. (`Major Updates to Rentor, and Payments Screens`)

### Added — Bills Screen & Relationships
- Updated Bills screen with improved layout.
- Established relationship between bills, email data, and rentors. (`Updated Bills Screen, Bill and Email Data and Rentor Relationship`)

### Fixed — Email & Bill Management
- Fixed up email parsing and bill management workflows. (`Fixed up email and bill management`)

### Fixed — Web Build
- Resolved compilation issues preventing the Flutter Web build from running. (`Fixes for web build to work`)

### Added — Initial Features
- Initial project scaffolding and first working build.
- Core data models: `Bill`, `Payment`, `Rentor`, `EmailData`.
- SQLite database with `DatabaseHelper` and schema migrations.
- Basic screens for bills, payments, and rentors.
- Gmail / IMAP email sync via Google Sign-In.
- Bills and payments parsing from email content and PDF attachments.
- Local notifications infrastructure. (`Initial Commit` / `Current Progress`)
