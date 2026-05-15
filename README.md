# Utility Bills Manager

A cross-platform Flutter application for tracking utility bills, managing rentor payments, and syncing bill data from Gmail — with CSV and PDF export.

## Features

- **Bill Management** — Create, edit, and delete utility bills (electric, gas, water, internet). Track due dates, amounts, and payment status (paid / partial / unpaid).
- **Payment Tracking** — Log payments, assign them to specific bills and rentors, and automatically reverse applied amounts when a payment is deleted.
- **Rentor Management** — Manage rentors, assign them to bills, track how much each owes, and record their last payment date. The add/edit form includes a **Calculate Amount Owed** button: select a month from periods that have unpaid or partial bills, and the app shows a per-bill-type breakdown of what the rentor still owes (accounting for their percentage overrides, excluded bill types, and payments already made). The calculated total is saved to a read-only field on the form.
- **Email Sync (Gmail)** — Sign in with Google to pull bill-related emails from your inbox. Parsed emails are matched to bills and payments automatically.
- **Summary Screen** — Monthly overview grouped by bill type, with "considered paid" threshold logic (e.g. electric/gas/water ≤ 30% unpaid treated as paid). Toggle visibility of actual unpaid amounts. A **Rentors Owed** card at the top of the screen shows what each rentor owes toward the current month's unpaid bills, broken down by bill type.
- **Export** — Export summaries as CSV or PDF, including per-bill rentor contributions.
- **Real-time Notifications** — Server-Sent Events (SSE) connection to the companion server pushes `newBill` / `newPayment` events instantly. Firebase Cloud Messaging (FCM) handles push notifications when the app is backgrounded. In-app notification bell with unread badge and slide-in panel.
- **Settings** — In-app settings accessible from every screen via a gear icon. `AppConfigScreen` lets you update the API base URL with a live reachability indicator. `ServerConfigScreen` lets you update IMAP credentials and email sync scheduling parameters directly from the app.
- **Local Notifications** — Bill due-date reminders via `flutter_local_notifications`.
- **In-App Update Checker** — On startup the app fetches `latest.json` from GitHub Pages and compares it to the running version using semver + build-number fallback. When a newer release is available a `MaterialBanner` appears at the top of every screen. Dismissal is per-version (stored in `SharedPreferences`) so the banner reappears only for new releases. On Windows a dialog offers all three installer formats (EXE, MSI, MSIX); on other platforms the platform-appropriate download URL is opened directly.
- **Cross-platform** — Runs on Android, iOS, macOS, Windows, Linux, and Web.

## Architecture

```
lib/
├── config/         # AppConfig (dart-define + encrypted local_secrets.json)
├── data/
│   ├── models/     # Bill, Payment, Rentor, EmailData, ServerConfig, AppState
│   └── repositories/ # ChangeNotifier singletons (Bills, Payments, Rentors, EmailData, ServerConfig)
├── database/       # db_factory with web/native/stub conditional exports
├── factory/
│   └── notification/ # NotificationServiceFactory — createNotificationService() returns platform-correct impl
├── helpers/        # Database, Bills, Payments, Rentors, Email, Configuration helpers
├── screens/        # UI screens per domain (bills, payments, rentors, emails, summary, settings)
├── services/
│   ├── api/        # ApiService facade + Bills/Rentors/Payments/EmailData/Config/Notification clients
│   ├── email/      # EmailService with web/native/stub conditional exports
│   ├── google/     # GoogleAccountService with web/native/stub conditional exports
│   ├── notification/ # NotificationService (abstract interface) + concrete native/web/windows impls; SseService
│   └── update/     # UpdateService (fetches latest.json, caches result) + UpdateInfo (semver comparison, per-platform download URLs)
├── widgets/        # Reusable widgets: NotificationBellIcon, NotificationPanel, SettingsIconButton, UpdateBanner
└── utils/
    ├── windows/    # DataMigration — one-time APPDATA path migration (com.example → AsanteDevs)
    └── ...         # Parsers, calculators, export, logger, dialogs
```

The app uses **SQLite** (`sqflite` / `sqflite_common_ffi` / `sqflite_common_ffi_web`) for local persistence with manual migrations (currently schema v15). The correct SQLite factory is selected at startup via a platform-conditional `db_factory`. Repositories are `ChangeNotifier` singletons that screens listen to for reactive updates.

Platform-specific behavior (database initialization, email/IMAP access, Google sign-in, SSE streaming, local notifications) is isolated behind conditional-export files (`_web`, `_native`, `_stub` variants) so the same codebase compiles cleanly on Android, iOS, macOS, Windows, Linux, and Web. The notification service uses a factory pattern: `NotificationService` is an abstract interface, and `createNotificationService()` (in `lib/factory/notification/`) returns the correct concrete implementation for each platform at startup.

**Firebase** (`firebase_core`, `firebase_auth`, `firebase_messaging`) is initialized at app startup. FCM handles push notifications when the app is backgrounded.

The app runs exclusively in **client mode**, talking to a companion Dart shelf server (`utility_bills_server`) via `ApiService`. The server exposes REST endpoints for all resources plus `/bill/list/sync`, `/payment/list/sync`, and `/email/list/sync` for on-demand email sync, a `/config` endpoint for managing IMAP credentials remotely, and `POST /device/token` for FCM push notification registration.

**Windows branding** — `Runner.rc` sets `CompanyName` to `AsanteDevs` and `ProductName` to `Utility Bills Manager`. These values drive the `%APPDATA%` path used by `path_provider` (`%APPDATA%\AsanteDevs\Utility Bills Manager\`). On first launch after upgrading from an older build, `DataMigration.runIfNeeded()` automatically moves data from the old path (`%APPDATA%\com.example\utility_bills_manager\`) to the new one so no data is lost.

## Getting Started

### Prerequisites

- Flutter SDK `^3.7.0`
- Dart SDK `^3.7.0`

### Configuration

The app reads secrets from `assets/config/local_secrets.json` (highest priority), `--dart-define` flags, or falls back to safe defaults.

#### Secrets file (first-time setup)

Create `assets/config/local_secrets.json` with your plaintext values:

```json
{
  "EMAIL_ADDRESS": "you@example.com",
  "EMAIL_PASSWORD": "your-app-password",
  "EMAIL_IMAP_SERVER": "imap.gmail.com",
  "EMAIL_IMAP_PORT": 993,
  "EMAIL_IMAP_SECURE": true
}
```

`local_secrets.json` is in `.gitignore` — it is never committed.

#### Encrypting the secrets

String values are encrypted at rest using AES-256-GCM. You need a 32-character key. Choose one and keep it safe (e.g. in a password manager).

Run the encryption script once from the project root:

```sh
dart run scripts/encrypt_secrets.dart --key=<your-32-char-key>
```

This overwrites `local_secrets.json` in place. String values become `enc:...` tokens; int/bool fields are left as-is. Re-running the script is safe — already-encrypted values are skipped.

After encrypting, pass the key at every build and run via `--dart-define=SECRETS_KEY=<your-32-char-key>`.

#### Platform build commands

```sh
# Android (debug — install directly on device)
flutter run --dart-define=SECRETS_KEY=<key>

# Android (release APK)
flutter build apk --dart-define=SECRETS_KEY=<key>

# Android (Play Store bundle)
flutter build appbundle --dart-define=SECRETS_KEY=<key>

# Web
flutter build web --dart-define=SECRETS_KEY=<key>

# Windows
flutter build windows \
  --dart-define=BUILD_TARGET=windows \
  --dart-define=SECRETS_KEY=<key>
```

The `--dart-define=BUILD_TARGET=windows` flag is required on Windows to select the correct notification service (`notification_service_windows.dart` uses `flutter_local_notifications_windows`; omitting it silently falls back to the native service which skips notifications on Windows).

#### Windows installers

Two installer scripts live in `windows/installer/`:

| File | Tool | Notes |
|------|------|-------|
| `setup.iss` | [InnoSetup](https://jrsoftware.org/isinfo.php) | Recommended for most users. Produces a single EXE. Prompts to remove user data on uninstall (default: keep). |
| `product.wxs` | [WiX Toolset v4](https://wixtoolset.org/) | Produces an MSI suitable for enterprise / IT deployment. Pass `REMOVE_USERDATA=1` to `msiexec` to opt in to data removal on uninstall. |

Both installers:
- Let the user choose the install directory.
- Detect an existing installation and offer an in-place upgrade.
- Close a running instance of the app automatically before upgrading.
- Store user data at `%APPDATA%\AsanteDevs\Utility Bills Manager\` (preserved across upgrades).

The CI workflow (`publish.yml`) builds both the EXE and MSI (as well as the MSIX package for the auto-update flow) and attaches them to the GitHub Release.

#### Android release signing

A keystore is required for release builds. The file `android/upload-keystore.jks` should exist locally (not in git). `android/key.properties` (also gitignored) must point to it:

```properties
storePassword=<keystore-password>
keyPassword=<key-password>
keyAlias=upload
storeFile=../upload-keystore.jks
```

To generate a new keystore:

```sh
keytool -genkey -v \
  -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

#### VS Code

`.vscode/launch.json` contains pre-configured run targets for Web (Chrome) and Windows. Update the `SECRETS_KEY` value in both args arrays to match your key if you regenerate it.

#### Firebase

- **Android** — `android/app/google-services.json` must be present (download from Firebase Console → Project settings → Android app).
- **iOS / macOS** — `ios/Runner/GoogleService-Info.plist` and `macos/Runner/GoogleService-Info.plist` must be present (download from Firebase Console → iOS/macOS app).
- **Linux** — Firebase is skipped at startup; SSE still works.

### Running

```sh
# Install dependencies
flutter pub get

# Run on a connected device / emulator (add --dart-define flags as above)
flutter run --dart-define=SECRETS_KEY=<key>
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `sqflite` / `sqflite_common_ffi` / `sqflite_common_ffi_web` | Cross-platform SQLite |
| `google_sign_in` / `googleapis` | Gmail OAuth & API access |
| `enough_mail` | IMAP email fetching |
| `pdf` / `pdfrx` | PDF generation and parsing |
| `share_plus` | File sharing / export |
| `flutter_local_notifications` | Due-date reminders |
| `intl` | Date/number formatting |
| `logger` | Structured logging via `AppLogger` |
| `firebase_core` / `firebase_auth` | Firebase initialization and authentication |
| `firebase_messaging` | FCM push notifications (Android, iOS, macOS, Web) |
| `uuid` | Unique IDs for `AppNotification` instances |
| `cryptography` | AES-256-GCM encryption/decryption for `local_secrets.json` values |
| `package_info_plus` | Reads the running app's version for the update checker |
| `url_launcher` | Opens download URLs from `UpdateBanner` in the system browser / file manager |

## License

Private — not published to pub.dev.
