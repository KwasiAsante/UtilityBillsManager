# Design: Reorganize Settings & Config Screen

**Date:** 2026-04-20
**Status:** Approved

---

## Problem

`ServerConfigScreen` groups all sync-related fields under a single "Sync Settings" card. This mixes two conceptually unrelated things:

- **Earliest Email Date** — the default start date for manual syncs (user-initiated)
- **Sync Delay / Sync Interval** — background polling configuration (automatic)

Users don't know what "Sync Delay" and "Sync Interval" control, or how they differ from the manual sync date. There are no labels or contextual hints.

---

## Solution

Split the "Sync Settings" card into two clearly named sections within `ServerConfigScreen`, and add always-visible `helperText` below each field in the sync sections.

No new screens. No structural changes to `SettingsScreen` or `AppConfigScreen`.

---

## Scope

**Changed:** `lib/screens/settings/server_config_screen.dart` only

---

## Section Structure (after)

### Email Account *(unchanged)*
- Email Address
- Email Password

### IMAP Settings *(unchanged)*
- IMAP Server
- IMAP Port
- Use Secure Connection (TLS)

### Manual Sync *(renamed from "Sync Settings", narrowed)*
- **Default Earliest Email Date**
  - Helper: *"The default start date used when you trigger a manual sync. You can override this each time in the sync dialog."*

### Background Sync *(new section, split out from "Sync Settings")*
- **Sync Delay (seconds)**
  - Helper: *"How long to wait after the app starts before the first background sync runs."*
- **Sync Interval (seconds)**
  - Helper: *"How often the app checks for new emails in the background. 900 = every 15 minutes."*

---

## Changes to `server_config_screen.dart`

1. Rename the "Sync Settings" section label to **"Manual Sync"**
2. Remove `Sync Delay` and `Sync Interval` fields from that card
3. Add a new **"Background Sync"** section label and card below, containing `Sync Delay` and `Sync Interval`
4. Add `helperText` to the three fields in the sync sections:
   - `Default Earliest Email Date` helper text
   - `Sync Delay` helper text
   - `Sync Interval` helper text
5. No field is removed, renamed in the data model, or reordered in the save logic

---

## Error Handling

No change — existing validation and save logic is untouched.

---

## Testing

- All three helper texts visible on screen without scrolling past their respective cards
- "Manual Sync" card contains only the date field
- "Background Sync" card contains only Sync Delay and Sync Interval
- Save still works correctly (same fields, same model)
- No regression in Email Account or IMAP sections
