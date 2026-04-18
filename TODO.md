# TODO / Future Implementation

---

## Email & Sync

- [ ] Add additional argument `latestEmailDate` to email sync methods and API request calls
  - [ ] Update `EmailDataHelper.syncEmails()` to accept optional `latestEmailDate` parameter
  - [ ] Pass `latestEmailDate` to server sync endpoints (`/bill/list/sync`, `/payment/list/sync`, `/email/list/sync`)
  - [ ] Server tracks and uses `latestEmailDate` for incremental syncs to improve performance

- [ ] Update sync/refresh date selection UI
  - [ ] Add optional end/latest date field to `SyncOptionsDialog`
  - [ ] End/latest date field is only enabled when earliest email date is selected
  - [ ] Reorganize `SettingsScreen` to clearly distinguish between:
    - Manual sync default earliest email date setting
    - Sync interval / background polling configuration

## App Configuration

- [ ] Create app configuration model
  - [ ] Define `AppConfiguration` class with app-specific settings
  - [ ] Include fields for sync intervals, notification preferences, user preferences, etc.

- [ ] Implement app configuration persistence
  - [ ] Save app configuration to `SharedPreferences`
  - [ ] Load app configuration from `SharedPreferences` on app startup
  - [ ] Provide methods to read and write individual configuration values

- [ ] Integrate app configuration throughout the app
  - [ ] Read configuration values from `SharedPreferences` or in-memory object
  - [ ] Apply configuration settings to relevant features (sync intervals, notifications, etc.)

## Background & Notifications

- [ ] Enable background notification support across all platforms
  - [ ] **Windows** — implement background listener for SSE or Firebase Cloud Messaging
  - [ ] **macOS** — implement background listener for SSE or Firebase Cloud Messaging
  - [ ] **iOS** — implement background listener for SSE or Firebase Cloud Messaging
  - [ ] **Android** — implement background listener for SSE or Firebase Cloud Messaging
  - [ ] Handle notification wake-ups and foreground/background transitions
  - [ ] Ensure app can receive and process notifications while running in background

## Rentor Messaging

- [ ] Craft messages for rentors
  - [ ] Generate per-rentor bill summary message (amount owed + due date)
  - [ ] Format message for clarity and professionalism
  - [ ] Support templating for customizable messages

- [ ] Send or share crafted messages to rentors
  - [ ] Implement message sharing via SMS (e.g., Twilio integration)
  - [ ] Provide "share text" feature so users can manually share messages
  - [ ] Support sharing via email, SMS, messaging apps, or other communication channels

## File Export

- [ ] Fix export of CSV and PDF files on Windows
  - [ ] Investigate Windows file permission and path handling issues
  - [ ] Ensure exported files are properly saved and accessible
  - [ ] Test CSV export on Windows
  - [ ] Test PDF export on Windows
  - [ ] Add error handling and user feedback for export failures

## UI/UX Improvements

- [ ] Reorganize Settings & Config Screen
  - [ ] Clearly separate manual sync email date settings from sync interval configuration
  - [ ] Improve visual hierarchy to reduce user confusion
  - [ ] Add informative labels and tooltips explaining each setting's purpose

