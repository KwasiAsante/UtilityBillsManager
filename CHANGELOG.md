# Changelog

All notable changes to this project are documented here.

---

## [Unreleased]

## [1.2.0+12] — 2026-08-20

### Fixed
- **Negative bill/payment amounts silently lost their sign** — `BillsParser`/`PaymentsParser`'s amount-extraction regexes only ever captured digits, so a credit amount like `-$360.00` in an email body was parsed as `360.00` and stored as a positive bill. Both parsers now detect a `-` immediately preceding a matched amount and negate the parsed value accordingly (`_parseSignedAmount`), mirroring the equivalent fix in `utility_bills_server` for consistency between the two codebases.
- **`BillsParser.inferStatus`** — a negative bill amount is abnormal (bills aren't expected to be credits), so it's now flagged as `PaymentStatus.unknown` for manual review instead of being guessed as `paid`.
- **`BillsParser`/`PaymentsParser.getAmountFromNextIndex`** — removed a filter that discarded a negative amount found on the line following a keyword (e.g. "total due"), which previously caused the parser to fall through and potentially pick up the wrong number.

## [1.2.0+11] — 2026-08-19

### Added
- **In-app log viewer** — new Settings → Logs screen (`LogViewerScreen`, `LogDetailScreen`, `LogFileService`) lists on-device log files (newest first), lets you open one to view its lines, and share a single file or all of them via the system share sheet. Useful for debugging when there's no debugger attached and the server log sink isn't reachable. `AppLogger.logsDirectory()` extracted as a shared helper so `_FileLogOutput` and `LogFileService` resolve the same platform-specific path instead of duplicating the logic.

### Changed
- **Configuration — `.env` replaces `local_secrets.json`** — app configuration (app mode, debug flag, API URL, and email credentials) is now stored in a `.env` file loaded at startup via `flutter_dotenv`. `.env` is gitignored and bundled as a Flutter asset; `.env.example` is committed as a template. `AppConfig` and `ServerConfiguration` now read all values from `dotenv.env` instead of `String/int/bool.fromEnvironment`.
- **`ServerConfiguration.init()`** — simplified startup: reloads DB config then calls `_seedFromEnv()`, which seeds the database from `.env` values when needed. Server mode always re-seeds (`.env` is authoritative); client mode only seeds on first run when no DB config exists. The `_LocalSecrets` AES-256-GCM decryption class and its asset-loading logic are removed entirely.
- **CI workflows** — all four build workflows (`publish.yml`, `firebase-hosting-merge.yml`, `firebase-hosting-pull-request.yml`) now create a minimal `.env` before building instead of the old `local_secrets.json` placeholder step.

### Removed
- **`local_secrets.json`** — bundled JSON asset used to seed email credentials at startup. Replaced by `.env`.
- **`scripts/encrypt_secrets.dart`** — CLI tool for AES-256-GCM encryption of `local_secrets.json` values. No longer needed.
- **`cryptography` package** — was only used for `local_secrets.json` decryption.

### Added
- **`flutter_dotenv 5.2.1`** — loads `.env` as a Flutter asset at runtime; `dotenv.load()` is the first async step in `main()`, with a silent fallback if the file is absent.
- **`AuthReloadMixin`** (`lib/screens/base/auth_reload_mixin.dart`) — mixin applied to all five list screens (Bills, Rentors, Payments, Emails, Summary). Registers an `AuthService` listener while the tab is selected and removes it when the tab is deselected or disposed. When `isLoggedIn` becomes `true`, calls each screen's `onAuthReload()` so data that failed to load due to an expired session is fetched automatically after the user logs back in.
- **Sign in button** — `MainTabScreen` now shows a `Sign in` button in the compact `AppBar` and the wide `NavigationRail` trailing slot when the user is not authenticated, providing an explicit entry point to `LoginScreen` without waiting for a server-triggered 401/403.

### Fixed
- **`ApiService.onUnauthorized` always set** — callback is now assigned in `main()` immediately after `AppConfig.init()` and before `runApp()`. Previously it was only set inside `_initialize()`, so if `_initialize()` threw before reaching `AuthService.loadFromPrefs()` the callback would remain null and 401/403 responses would never trigger the login prompt.
- **401 now triggers login prompt** — `LoggingHttpClient` previously only called `onUnauthorized` on HTTP 403; it now also fires on 401 (the status most auth backends return for an expired or missing token).
- **Duplicate login screen prevented** — `MainTabScreen._onAuthChanged` now guards navigation with a `_loginScreenVisible` flag. Background API calls that return 401/403 while the login screen is already showing no longer push a second `LoginScreen` on top.
- **`clearUnauthorized()` timing** — previously called before navigating to `LoginScreen`, which reset `_pendingUnauthorized` immediately and allowed background 401/403 responses to re-trigger the prompt. It is now called in the `Navigator.push` `whenComplete` callback, keeping the flag set for the entire duration the login screen is visible.
- **`pendingUnauthorized` race** — `MainTabScreen.initState` now checks `_authService.pendingUnauthorized` at mount time and dispatches `_onAuthChanged` via `addPostFrameCallback`. This catches the case where a 401/403 arrived during `_initialize()` before `MainTabScreen` existed and `notifyListeners()` fired with no listeners registered.

## [1.1.0] — 2026-04-17

### Changed
- **Notification service factory pattern** — `notification_service.dart` is now an abstract `interface class NotificationService` instead of a conditional-export shim. A new `lib/factory/notification/` directory holds the factory entry point (`notification_service_factory.dart`) and platform-specific factory implementations (`notification_service_factory_native.dart`, `notification_service_factory_web.dart`). `main.dart` calls `createNotificationService()` at startup to obtain the correct concrete instance. `notification_service_base.dart` removed — its shared state and helpers have been absorbed into the platform implementations.
- **Android build configuration** — `build.gradle.kts`, `settings.gradle.kts`, and `gradle-wrapper.properties` updated to align with the latest AGP and Kotlin plugin versions; added a second Android run configuration (`.run_android/Utility Bills (Android) My Phone.run.xml`).

### Added
- **Calculate Amount Owed (Rentor form)** — New button on `AddEditRentorScreen` that calculates what the rentor owes for a selected month:
  - Clicking the button opens a period-selection dialog whose dropdown is limited to year/month combinations that have at least one unpaid or partial bill.
  - After selecting a period, a breakdown dialog shows the owed amount per bill type, accounting for the rentor's per-type percentage overrides (falling back to `defaultPercentage`), excluded bill types, and payments the rentor has already made toward each bill. If the rentor has paid their full share of a bill, that bill contributes $0.
  - Confirming the result saves it (in-memory only) to a read-only "Amount Owed" field next to the button, formatted as `"MMMM yyyy – $0.00"`.
- **Rentors Owed card (Summary screen)** — A collapsible card above the Monthly / By Bill Type tabs shows what each rentor owes toward the current month's unpaid or partial bills. Per-rentor rows list the owed amount broken down by bill type; rentors who have paid their full share show "All settled". The card is hidden while data is loading and shows a placeholder message when there are no unpaid bills for the current month.
- **Secrets encryption** — `local_secrets.json` string values (email credentials) are now encrypted at rest using AES-256-GCM via the `cryptography` package. `_LocalSecrets.loadFromAsset` decrypts all `enc:`-prefixed values at startup using the key from `--dart-define=SECRETS_KEY=<32-char-key>`. Non-string fields (port, secure flag) remain as plaintext. `scripts/encrypt_secrets.dart` is a standalone CLI tool for encrypting the file: `dart run scripts/encrypt_secrets.dart --key=<key>`.

### Changed
- **Settings UI** — `SettingsScreen` landing page accessible from a new `SettingsIconButton` in every tab's `AppBar`. Sub-screens:
  - `AppConfigScreen` — edit the API base URL; live reachability indicator turns green/red as the URL is typed; validates URL format before saving.
  - `ServerConfigScreen` — full form for IMAP credentials (address, password, server, port, secure flag), email earliest-date, and sync schedule parameters; loads existing `ServerConfig` on open and writes via `ServerConfigRepository`.
- **Bundle ID** updated from `com.example.utility_bills_manager` to `com.asante.utility_bills_manager` across Android `build.gradle.kts`, `MainActivity.kt`, iOS/macOS Xcode projects, and `firebase_options.dart`. Android release signing config (`key.properties` + keystore) wired into `build.gradle.kts`.
- **`calculateOwedBreakdown`** extracted from inline loops in `SummaryScreen` and `AddEditRentorScreen` to `RentorExtensions` in `rentor.dart`. Both screens now call the shared method. Accepts a `percentageForType` callback so form-state percentages are used during editing without persisting a temp object.
- **`shouldAbortWebSync`** extracted to `GoogleSignInScreenState` base class. Bills, payments, emails, and summary screens now call a single `shouldAbortWebSync(entityName)` instead of each duplicating the 9-line web/Google sign-in guard. Also fixes a bug where `_loading` was not reset to `false` before the early return on summary screen.
- **Notification service platform guards** — `notification_service_native.dart` now skips local-notification and FCM initialisation on Windows and Linux. Windows is skipped because its notification support lives in `notification_service_windows.dart` (selected via `--dart-define=BUILD_TARGET=windows`); loading the wrong plugin would crash. Linux is skipped because no Firebase config exists for it. SSE still connects on both platforms.
- **`notification_service.dart` conditional export** — `dart.library.io` was incorrectly selecting the native service on all native platforms including Windows; corrected to `if (BUILD_TARGET == 'windows')` dart-define check so the Windows-specific service is only selected when explicitly targeted.
- **`dart.library.html` → `dart.library.js_interop`** in conditional exports for `db_factory`, `email_service`, and `google_account_service`. `dart.library.html` is deprecated in Dart 3 and not reliable in newer Flutter web builds.
- **`ServerConfigScreen._validateInt`** — added `allowZero` parameter (used for sync delay); fixed truncated error message.
- **`Rentor.calculateOwedAmount`** — now falls back to `defaultPercentage` instead of `0.0` when no per-type override is set. Returns `0.0` only for explicitly excluded bill types.
- **`@protected`** added to `sseEventsSubscription` and `initialized` in `NotificationServiceBase`; added to all mutable fields in `SseServiceBase` (`eventController`, `state`, `baseDelayMs`, `attempt`, `reconnectTimer`, `serverUrl`, `deviceId`).
- **`BillCalculator`** (`lib/utils/bills/bills_calculator.dart`) removed — its logic is superseded by `Rentor.calculateOwedAmount` and `RentorExtensions.calculateOwedBreakdown`.

### Fixed
- **Android** `AndroidManifest.xml`: added `INTERNET` permission (`uses-permission`); corrected pre-existing `user-permission` typo to `uses-permission` for `RECEIVE_BOOT_COMPLETED`.
- **macOS entitlements**: added `com.apple.security.network.client` to both `DebugProfile.entitlements` and `Release.entitlements`; without it the app cannot make outbound HTTP/HTTPS requests under the macOS sandbox.
- **`web/index.html`**: updated page title, Apple web-app title, and description meta tag from Flutter template defaults.
- **`main.dart`**: `Firebase.initializeApp` is now skipped on Linux (`defaultTargetPlatform != TargetPlatform.linux`) since no Firebase config exists for Linux; previously this would throw at startup.
- **`email_data_helper.dart`**: fixed logic inversion — `if (bill != null)` was incorrectly calling `createBill` when a bill already existed, causing duplicate bill creation; corrected to `if (bill == null)`.
- **`bills_helper.dart`**: `updateLastPaymentStatus` — when a `Rentor` is provided, payments are not applied to bill types in `excludedBillTypes` (intentional; documented with inline comment).
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

### Added — API and email query helpers
- `Payment.toJson`: optional `include` map parameter — passing `{'bill': true}` appends `billIds` and `{'rentor': true}` ensures `rentorId` is present in the serialized output.
- `DatabaseHelper.readEmail` / `EmailDataHelper.readEmail`: new `queryByEmailId` flag to query email records by `emailId` (IMAP message ID) instead of the default `emailDataId` primary key.
- `SummaryScreen`: `fetchPaymentEmails()` is now called alongside `fetchBillEmails()` during Gmail sync so payment-related emails are also fetched.

### Added — Responsive layout, adaptive chrome, and platform assets
- **`AppBreakpoints` and `ResponsiveConstraint`** — 600dp breakpoint; max-width centering on wide screens; widget tests assert `ConstrainedBox` max width in wide layouts.
- **`MainTabScreen`** — `NavigationRail` when `AppBreakpoints.isWide`; adaptive navigation doc comments.
- **List and form screens** — Consolidated `AppBar` actions on Bill, Rentor, Payment, Email, and Summary screens; `ResponsiveConstraint` (max width 560) on settings and form flows; `EditEmailDataScreen` `ResponsiveConstraint` import/placement fix.
- **Adaptive dialogs** — `DueDateFilterSheet` chooses dialog vs bottom sheet by width; dialog mode guards `viewInsets` bottom padding. Assign Bills / Assign Rentor in `AddEditPaymentScreen` share an extracted adaptive content widget.
- **List screen polish** — `BillListScreen` overflow menu aligned with other lists (`CheckedPopupMenuItem`, tooltips, `contentPadding`); search clear control restored; `PopupMenuButton<String>` standardization; removed unintended `PaymentListScreen` search field; `RentorListScreen` menu typing and formatting fixes.
- **Icons and manifests** — Web, Windows, macOS, and iOS app icons/resources; Android adaptive launcher icons; Android manifest updates; Android launcher icon assets.
- **Tooling** — Dependency and Gradle/build configuration updates; responsive layout design spec; TODO doc and project icon asset; `.worktrees/` added to `.gitignore`.

---

## [1.0.0]

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
