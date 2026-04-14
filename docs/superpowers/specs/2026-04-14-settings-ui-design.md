# Settings UI Design

**Date:** 2026-04-14
**Status:** Approved

## Overview

Add a settings UI to the Utility Bills Manager app. A gear icon in each tab screen's `AppBar` opens a `SettingsScreen` landing page. From there the user navigates to one of two independent sub-screens: **App Configuration** (API base URL) or **Server Configuration** (email credentials, IMAP settings, sync scheduling). Each sub-screen has its own Save button and saves only its own section.

---

## Architecture

### New Files
- `lib/screens/settings/settings_screen.dart` — landing screen with two navigation tiles
- `lib/screens/settings/app_config_screen.dart` — App Configuration form
- `lib/screens/settings/server_config_screen.dart` — Server Configuration form
- `lib/widgets/settings_icon_button.dart` — reusable `IconButton` (`Icons.settings`) that pushes `SettingsScreen`

### Modified Files
- `lib/screens/bills/bill_list_screen.dart` — add `SettingsIconButton` to `AppBar` actions
- `lib/screens/rentors/rentor_list_screen.dart` — add `SettingsIconButton` to `AppBar` actions
- `lib/screens/summary/summary_screen.dart` — add `SettingsIconButton` to `AppBar` actions
- `lib/screens/payments/payment_list_screen.dart` — add `SettingsIconButton` to `AppBar` actions
- `lib/screens/emails/email_list_screen.dart` — add `SettingsIconButton` to `AppBar` actions

### Entry Point
The `SettingsIconButton` widget (`Icons.settings`) is added to the `actions` of each of the 5 tab screens' existing `AppBar`s. Tapping it calls `Navigator.push` to open `SettingsScreen`. No changes to `MainTabScreen`.

---

## UI Layout

### SettingsScreen (Landing)
A `StatelessWidget` with:
- `Scaffold` with `AppBar(title: Text('Settings'))`
- `body: ListView` with two `ListTile`s:
  - "App Configuration" → `Navigator.push` to `AppConfigScreen`
  - "Server Configuration" → `Navigator.push` to `ServerConfigScreen`
- Both tiles have a `trailing: Icon(Icons.chevron_right)`

---

### AppConfigScreen
A `StatefulWidget` with:
- `Scaffold` with `AppBar(title: Text('App Configuration'))`
- `body: SingleChildScrollView` containing a `Column`

| Field | Widget | Source |
|---|---|---|
| API Base URL | `TextFormField` | `AppConfig.apiBaseUrl` |

- `FilledButton(text: 'Save')`, full width, at the bottom
- Shows `SnackBar('App configuration saved')` on success
- Shows `SnackBar('Failed to save: $e')` on error

---

### ServerConfigScreen
A `StatefulWidget` with:
- `Scaffold` with `AppBar(title: Text('Server Configuration'))`
- `body: SingleChildScrollView` containing a `Column`

| Field | Widget | Source |
|---|---|---|
| Email Address | `TextFormField` | `ServerConfiguration.emailAddress` |
| Email Password | `TextFormField` (obscured, show/hide toggle) | `ServerConfiguration.emailPassword` |
| IMAP Server | `TextFormField` | `ServerConfiguration.emailImapServer` |
| IMAP Port | `TextFormField` (numeric keyboard) | `ServerConfiguration.emailImapPort` |
| IMAP Secure | `SwitchListTile` | `ServerConfiguration.emailImapSecure` |
| Earliest Email Date | `TextFormField` + calendar `suffixIcon` → `showDatePicker` | `ServerConfiguration.emailEarliestDate` |
| Sync Delay (seconds) | `TextFormField` (numeric keyboard) | `ServerConfiguration.emailSyncDelayDuration` |
| Sync Interval (seconds) | `TextFormField` (numeric keyboard) | `ServerConfiguration.emailSyncInterval` |

- `FilledButton(text: 'Save')`, full width, at the bottom
- Shows `SnackBar('Server configuration saved')` on success
- Shows `SnackBar('Failed to save: $e')` on error

---

## Data Flow

### AppConfigScreen — Loading (initState)
- `AppConfig.apiBaseUrl` → API URL `TextEditingController`

### AppConfigScreen — Saving (_saveSettings)
Wrapped in `try/catch`. Calls:
1. `AppConfig.setApiBaseUrl(apiUrlController.text)`

---

### ServerConfigScreen — Loading (initState)
All reads synchronous (from `Preferences` cache pre-warmed at startup):
- `ServerConfiguration.*` getters → controllers + `_imapSecure` bool

### ServerConfigScreen — Saving (_saveSettings)
Wrapped in `try/catch`. Calls in sequence:
1. `ServerConfiguration.setEmailAddress(...)`
2. `ServerConfiguration.setEmailPassword(...)`
3. `ServerConfiguration.setEmailImapServer(...)`
4. `ServerConfiguration.setEmailImapPort(...)`
5. `ServerConfiguration.setEmailImapSecure(...)`
6. `ServerConfiguration.setEmailEarliestDate(...)`
7. `ServerConfiguration.setEmailSyncDelayDuration(...)`
8. `ServerConfiguration.setEmailSyncInterval(...)`

---

## Validation

| Field | Rule |
|---|---|
| IMAP Port | Must be a valid integer (`int.tryParse`). Show inline `errorText` if invalid; block save. |
| Sync Delay | Must be a valid integer. Show inline `errorText` if invalid; block save. |
| Sync Interval | Must be a valid integer. Show inline `errorText` if invalid; block save. |
| All other fields | No mandatory validation — empty values fall back to runtime defaults. |

---

## Styling

- Material 3 throughout — consistent with the rest of the app
- Section titles use `Text` with `Theme.of(context).textTheme.titleMedium`
- No external packages required (`settings_ui` not used)
