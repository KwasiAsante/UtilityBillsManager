# Utility Bills Manager

A cross-platform Flutter application for tracking utility bills, managing rentor payments, and syncing bill data from Gmail — with CSV and PDF export.

## Features

- **Bill Management** — Create, edit, and delete utility bills (electric, gas, water, internet). Track due dates, amounts, and payment status (paid / partial / unpaid).
- **Payment Tracking** — Log payments, assign them to specific bills and rentors, and automatically reverse applied amounts when a payment is deleted.
- **Rentor Management** — Manage rentors, assign them to bills, track how much each owes, and record their last payment date.
- **Email Sync (Gmail)** — Sign in with Google to pull bill-related emails from your inbox. Parsed emails are matched to bills and payments automatically.
- **Summary Screen** — Monthly overview grouped by bill type, with "considered paid" threshold logic (e.g. electric/gas/water ≤ 30% unpaid treated as paid). Toggle visibility of actual unpaid amounts.
- **Export** — Export summaries as CSV or PDF, including per-bill rentor contributions.
- **Real-time Notifications** — Server-Sent Events (SSE) connection to the companion server pushes `newBill` / `newPayment` events instantly. Firebase Cloud Messaging (FCM) handles push notifications when the app is backgrounded. In-app notification bell with unread badge and slide-in panel.
- **Settings** — In-app settings accessible from every screen via a gear icon. `AppConfigScreen` lets you update the API base URL with a live reachability indicator. `ServerConfigScreen` lets you update IMAP credentials and email sync scheduling parameters directly from the app.
- **Local Notifications** — Bill due-date reminders via `flutter_local_notifications`.
- **Cross-platform** — Runs on Android, iOS, macOS, Windows, Linux, and Web.

## Architecture

```
lib/
├── config/         # AppConfig (dart-define + local_secrets.json)
├── data/
│   ├── models/     # Bill, Payment, Rentor, EmailData, ServerConfig, AppState
│   └── repositories/ # ChangeNotifier singletons (Bills, Payments, Rentors, EmailData, ServerConfig)
├── database/       # db_factory with web/native/stub conditional exports
├── helpers/        # Database, Bills, Payments, Rentors, Email, Configuration helpers
├── screens/        # UI screens per domain (bills, payments, rentors, emails, summary, settings)
├── services/
│   ├── api/        # ApiService facade + Bills/Rentors/Payments/EmailData/Config/Notification clients
│   ├── email/      # EmailService with web/native/stub conditional exports
│   ├── google/     # GoogleAccountService with web/native/stub conditional exports
│   └── notification/ # NotificationService & SseService (base + native/web/windows variants)
├── widgets/        # Reusable widgets: NotificationBellIcon, NotificationPanel, SettingsIconButton
└── utils/          # Parsers, calculators, export, logger, dialogs
```

The app uses **SQLite** (`sqflite` / `sqflite_common_ffi` / `sqflite_common_ffi_web`) for local persistence with manual migrations (currently schema v15). The correct SQLite factory is selected at startup via a platform-conditional `db_factory`. Repositories are `ChangeNotifier` singletons that screens listen to for reactive updates.

Platform-specific behavior (database initialization, email/IMAP access, Google sign-in, SSE streaming, local notifications) is isolated behind conditional-export files (`_web`, `_native`, `_stub` variants) so the same codebase compiles cleanly on Android, iOS, macOS, Windows, Linux, and Web.

**Firebase** (`firebase_core`, `firebase_auth`, `firebase_messaging`) is initialized at app startup. FCM handles push notifications when the app is backgrounded.

The app runs exclusively in **client mode**, talking to a companion Dart shelf server (`utility_bills_server`) via `ApiService`. The server exposes REST endpoints for all resources plus `/bill/list/sync`, `/payment/list/sync`, and `/email/list/sync` for on-demand email sync, a `/config` endpoint for managing IMAP credentials remotely, and `POST /device/token` for FCM push notification registration.

## Getting Started

### Prerequisites

- Flutter SDK `^3.7.0`
- Dart SDK `^3.7.0`

### Configuration

The app reads secrets from `assets/config/local_secrets.json` (highest priority), `--dart-define` flags, or falls back to safe defaults.

Create `assets/config/local_secrets.json` (keep out of version control):

```json
{
  "EMAIL_ADDRESS": "you@example.com",
  "EMAIL_PASSWORD": "your-app-password",
  "EMAIL_IMAP_SERVER": "imap.gmail.com",
  "EMAIL_IMAP_PORT": 993,
  "EMAIL_IMAP_SECURE": true,
  "EMAIL_EARLIEST_DATE": "2024-01-01"
}
```

Alternatively, pass values at build time:

```sh
flutter run \
  --dart-define=EMAIL_ADDRESS=you@example.com \
  --dart-define=EMAIL_PASSWORD=your-app-password \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

### Running

```sh
# Install dependencies
flutter pub get

# Run (debug)
flutter run

# Build for web
flutter build web
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

## License

Private — not published to pub.dev.
