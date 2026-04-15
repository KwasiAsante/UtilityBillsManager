# Changelog

All notable changes to this project are documented here.

---

## [Unreleased]

### Added
- **Settings UI** — `SettingsScreen` landing page accessible from a new `SettingsIconButton` in every tab's `AppBar`. Sub-screens:
  - `AppConfigScreen` — edit the API base URL; live reachability indicator turns green/red as the URL is typed; validates URL format before saving.
  - `ServerConfigScreen` — full form for IMAP credentials (address, password, server, port, secure flag), email earliest-date, and sync schedule parameters; loads existing `ServerConfig` on open and writes via `ServerConfigRepository`.
- **Platform-specific services** — service layer split into conditional imports with `_native`, `_web`, and `_stub` variants so the app compiles on all platforms without `dart:io` / plugin gaps:
  - `db_factory` (web / native / stub) — calls `initDb()` from `main.dart` to pick the correct `sqflite` factory per platform.
  - `EmailService` (web / native / stub) — platform-aware IMAP fetch; web variant uses Gmail REST API while native uses `enough_mail`.
  - `GoogleAccountService` (web / native / stub) — platform-aware Google sign-in; web uses `google_sign_in_web`, native uses `google_sign_in`.
  - `NotificationService` (native / web / windows variants) — `NotificationServiceBase` abstract class; `NotificationServiceNative` handles FCM + local notifications on Android/iOS/macOS; `NotificationServiceWeb` uses the browser Notifications API; `NotificationServiceWindows` is a no-op stub.
  - `SseService` (native / web variants) — `SseServiceBase` abstract class; `SseServiceNative` uses `http` streaming; `SseServiceWeb` uses the browser `EventSource` API.
- **Firebase** — added `firebase_core` and `firebase_auth`; `Firebase.initializeApp` called in `main.dart` with generated `firebase_options.dart`; Android `google-services.json` and Gradle plugin wiring added; Firebase Core/Auth registered in macOS and Windows plugin registrants.
- `WINDOWS_BUILD_ERROR_SOLUTION.md` — troubleshooting guide for Windows build errors related to notification plugins.
- `SseService` (`lib/services/notification/sse_service.dart`) — persistent Server-Sent Events client for the `/connect` endpoint. Exposes a broadcast `Stream<SseEvent>`. Reconnects automatically with exponential back-off (5 s base, 60 s cap); a `retry:` field from the server overrides the base delay. Explicit `disconnect()` cancels all reconnect attempts.
- `NotificationService` (`lib/services/notification/notification_service.dart`) — singleton that orchestrates SSE and Firebase Cloud Messaging (FCM). Initialises `flutter_local_notifications`, requests FCM permission, registers the device token via `NotificationApiService`, and subscribes to `SseService.events`. On each `SseEvent` it shows a local system notification, adds an `AppNotification` to `AppNotificationStore`, and reloads the relevant repository (`BillsRepository` or `PaymentsRepository`). FCM background handler registered as a top-level isolate entry-point.
- `AppNotificationStore` (`lib/services/notification/app_notification_store.dart`) — in-memory `ChangeNotifier` list of `AppNotification` items. Supports `add`, `markRead`, `markAllRead`, and `clear`.
- `AppNotification` model (`lib/data/models/app_notification.dart`) — lightweight notification value object with `id`, `title`, `body`, `type`, `isRead`, and `createdAt`.
- `SseEvent` model (`lib/data/models/sse_event.dart`) — typed wrapper for SSE payloads; parses `event:` / `data:` lines and maps known event names to `SseEventType` (`newBill`, `newPayment`).
- `NotificationBellIcon` widget (`lib/widgets/notification_bell_icon.dart`) — `AppBar` action icon with an animated unread-count badge. Tapping opens `NotificationPanel`.
- `NotificationPanel` widget (`lib/widgets/notification_panel.dart`) — slide-in drawer listing `AppNotification` items with mark-read and clear-all actions.
- `ServerConfig` model (`lib/data/models/server_config.dart`) — client-side mirror of the server's `Configuration` model. Stores IMAP credentials and email sync scheduling parameters. `toJson`/`fromJson` share the same wire format as the server so they interoperate without conversion. `emailImapSecure` tolerates both integer (0/1) and boolean string forms on deserialisation.
- `DatabaseHelper` v15: new `configuration` table (9 columns). `_onCreate` creates the table; `_onUpgrade` adds it via `CREATE TABLE IF NOT EXISTS` for existing installs. New CRUD methods: `createConfiguration` (clears before insert to enforce single-row invariant), `readConfiguration`, `updateConfiguration`, `deleteConfiguration`.
- `ConfigApiService` (`ApiService.config()`): new singleton HTTP client for `/config` endpoints. Methods `getConfig`, `createConfig`, `updateConfig`, `deleteConfig` now accept/return typed `ServerConfig` objects instead of raw maps.
- `NotificationApiService` (`ApiService.notifications()`): new singleton HTTP client with `registerDeviceToken(deviceId, fcmToken)` for `POST /device/token`.
- Sync endpoints on existing API service classes: `BillsApiService.getSyncedBills`, `PaymentsApiService.getSyncedPayments`, and `EmailDataApiService.getSyncedEmailData` — each calls the corresponding `/list/sync` route and returns `null` on HTTP 409 (sync already in progress).
- `ServerConfigHelper` (`lib/helpers/configuration/server_config_helper.dart`) — singleton service layer that routes configuration CRUD to `DatabaseHelper` (local mode) or `ConfigApiService` (API mode), following the same pattern as all other helpers.
- `ServerConfigRepository` (`lib/data/repositories/server_config_repository.dart`) — singleton `ChangeNotifier` repository. Holds a single nullable `ServerConfig?` in memory; `create`/`update`/`delete` call `reload` and `notifyListeners` on success.

### Changed
- **Local server removed** — `lib/services/api/local_server.dart` and `local_server_stub.dart` deleted; the app no longer embeds a shelf HTTP server. Server mode is handled by the separate `utility_bills_server` package.
- `ApiService.baseUrl` default restored to `http://127.0.0.1:8080` (was temporarily `9090`).
- `main.dart` simplified: Firebase initialization added; local-server start and commented notification scaffolding removed; `initDb()` called for platform DB factory setup.
- `AppConfig`: default `APP_MODE` changed from `server` to `client`; fallback in `mode` getter now also returns `AppMode.client`.
- `AddEditPaymentScreen`: switched from `PaymentsHelper` to `PaymentsRepository` for create/update; fixed bill due-date display to use `DateFormat('yyyy-MM-dd')` instead of raw `DateTime.toString()`.
- `AddEditRentorScreen`: removed unused `_calculateAmountOwed()` method and its "Amount Owed" UI field; removed unused `BillsHelper` and `Payment` imports.
- `ApiService` (payments): `createPayment` and `updatePayment` now serialize via `toJson(include: {'bill': true, 'rentor': true})` so bill IDs and rentor ID are sent to the API; `getPayments` now maps `billList` from the response into full `Bill` objects via `Payment.fromJson`.
- `ApiService` (emails): `getEmail` forwards a `query_by_email_id` query parameter to the API.

### Fixed
- `SseService`: `catchError` handler now returns a `Response` object, resolving a Dart type-warning about the return type of the error callback.
- `EmailDataRepository`: `deleteEmailData` and `deleteAllEmailData` now call `sync()` after deletion so the in-memory list stays consistent with the local database.
- `SummaryScreen._isConsideredPaid`: bills with `PaymentStatus.paid` are now always treated as paid regardless of threshold calculation.

### Added (prior entries)
- `Payment.toJson`: optional `include` map parameter — passing `{'bill': true}` appends `billIds` and `{'rentor': true}` ensures `rentorId` is present in the serialized output.
- `DatabaseHelper.readEmail` / `EmailDataHelper.readEmail`: new `queryByEmailId` flag to query email records by `emailId` (IMAP message ID) instead of the default `emailDataId` primary key.
- `SummaryScreen`: `fetchPaymentEmails()` is now called alongside `fetchBillEmails()` during Gmail sync so payment-related emails are also fetched.

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
