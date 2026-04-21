# TODO / Future Implementation

---

## Email & Sync

- [x] Add additional argument `latestEmailDate` to email sync methods and API request calls
  - [x] Update `EmailDataHelper.syncEmails()` to accept optional `latestEmailDate` parameter
  - [x] Pass `latestEmailDate` to server sync endpoints (`/bill/list/sync`, `/payment/list/sync`, `/email/list/sync`)
  - [ ] Server tracks and uses `latestEmailDate` for incremental syncs to improve performance

- [x] Update sync/refresh date selection UI
  - [x] Add optional end/latest date field to `SyncOptionsDialog`
  - [x] End/latest date field is only enabled when earliest email date is selected
  - [x] Reorganize `SettingsScreen` to clearly distinguish between:
    - Manual sync default earliest email date setting
    - Sync interval / background polling configuration

## App Configuration

- [x] Create app configuration model
  - [x] Define `AppConfiguration` class with app-specific settings (`baseWebAPI`)
  - [ ] Include fields for sync intervals, notification preferences, user preferences, etc.

- [x] Implement app configuration persistence
  - [x] Save app configuration to SQLite (persists reliably on web via IndexedDB)
  - [x] Load app configuration from SQLite on app startup (`AppConfig.load()`)
  - [x] Provide methods to read and write individual configuration values

- [x] Integrate app configuration throughout the app
  - [x] `apiBaseUrl` reads from SQLite-backed cache first, then falls back to SharedPreferences → dart-define → default

## Background & Notifications

- [x] Enable background notification support across all platforms
  - [x] **Windows** — SSE lifecycle observer reconnects on app resume
  - [x] **macOS** — APS environment entitlements + lifecycle SSE reconnect
  - [x] **iOS** — UIBackgroundModes (remote-notification, fetch) + lifecycle SSE reconnect
  - [x] **Android** — POST_NOTIFICATIONS permission + data-only FCM handler + lifecycle SSE reconnect
  - [x] Handle notification wake-ups and foreground/background transitions
  - [x] Ensure app can receive and process notifications while running in background

## Rentor Messaging

- [x] Craft messages for rentors
  - [x] Generate per-rentor bill summary message (amount owed + due date)
  - [x] Format message for clarity and professionalism
  - [x] Support templating for customizable messages

- [x] Send or share crafted messages to rentors
  - [ ] Implement message sharing via SMS (e.g., Twilio integration)
  - [x] Provide "share text" feature so users can manually share messages
  - [x] Support sharing via email, SMS, messaging apps, or other communication channels

## File Export

- [x] Fix export of CSV and PDF files on Windows
  - [x] Investigate Windows file permission and path handling issues
  - [x] Ensure exported files are properly saved and accessible
  - [x] Test CSV export on Windows
  - [x] Test PDF export on Windows
  - [x] Add error handling and user feedback for export failures

## UI/UX Improvements

- [x] Reorganize Settings & Config Screen
  - [x] Clearly separate manual sync email date settings from sync interval configuration
  - [x] Improve visual hierarchy to reduce user confusion
  - [x] Add informative labels and tooltips explaining each setting's purpose

