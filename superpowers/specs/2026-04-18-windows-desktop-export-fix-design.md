# Design: Fix CSV and PDF Export on Desktop (Windows, macOS, Linux)

**Date:** 2026-04-18
**Status:** Approved

---

## Problem

Export of CSV and PDF files fails on Windows desktop. The app uses `share_plus` to share files via the Windows Share contract, but regular (non-UWP) Flutter desktop apps have no valid share targets — Windows shows "Try that again / We couldn't show you all the ways you could share." The same issue applies to macOS and Linux desktop where the share sheet is unavailable or unreliable for files.

---

## Solution

On desktop platforms (Windows, macOS, Linux), replace the `share_plus` share flow with a native Save As dialog using the `file_selector` package (`getSaveLocation()`). On mobile and web, the existing `share_plus` flow is unchanged.

---

## Scope

**Changed:** `lib/utils/export_utils.dart`
**New dependency:** `file_selector` (Flutter team's package)
**Unchanged:** `summary_screen.dart`, error handling, mobile/web behaviour

---

## Data Flow

### CSV Export (desktop)
1. Build CSV string buffers per month (unchanged)
2. For each month, call `getSaveLocation()` with:
   - Suggested filename: `bills_<Month_YYYY>.csv`
   - File type filter: `.csv`
3. If user cancels (`null` returned), skip that file silently
4. Write UTF-8 bytes to the chosen path via `dart:io` `File.writeAsBytes()`

### PDF Export (desktop)
1. Build PDF document (unchanged)
2. Call `getSaveLocation()` once with:
   - Suggested filename: `bills_export.pdf`
   - File type filter: `.pdf`
3. If user cancels, do nothing
4. Write PDF bytes to the chosen path via `dart:io` `File.writeAsBytes()`

### Mobile / Web
No change — `SharePlus.instance.share()` is called as before.

---

## Platform Detection

Use `dart:io` `Platform` class:

```dart
import 'dart:io';

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
```

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| User cancels Save As dialog | Silent no-op |
| File write fails (e.g. permission denied) | Exception propagates to `summary_screen.dart` `try/catch`, shows red snackbar |

No new UI required.

---

## Testing

- Export CSV on Windows: Save As dialog opens, file saved to chosen path, correct content
- Export PDF on Windows: Save As dialog opens, file saved to chosen path, correct content
- Cancel dialog: no error shown, no file written
- Export on Android/iOS: existing share sheet behaviour unchanged