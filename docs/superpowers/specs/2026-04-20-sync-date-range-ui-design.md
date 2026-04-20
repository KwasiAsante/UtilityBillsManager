# Design: Sync Dialog Date Range UI

**Date:** 2026-04-20
**Status:** Approved

---

## Problem

`SyncOptionsDialog` lets users pick a single "earliest email date" (lower bound) for a manual sync. There is no way to set an upper bound. The server already supports a `latestEmailDate` query param on all three sync endpoints — but the client never sends it.

This task (Task 3 of 4) adds the UI to capture a latest date. Wiring it through to the API is Task 4.

---

## Scope

**Changed:** `lib/utils/dialogs/sync_options_dialog.dart` only

No changes to callers (`bill_list_screen.dart`, `payment_list_screen.dart`, `email_list_screen.dart`, `summary_screen.dart`), `EmailDataHelper`, or any API service. Those are Task 4.

---

## Data Model

`SyncOptions` gains one new field:

```dart
class SyncOptions {
  final DateTime? earliestDate;
  final DateTime? latestDate;   // NEW
  final int? maxEmails;

  const SyncOptions({this.earliestDate, this.latestDate, this.maxEmails});
}
```

---

## UI Design

### Layout

The existing single `ListTile` date picker is replaced with an inline **"From → To" chip row**: a `Row` with two `Expanded` `InkWell`-wrapped chip cards and an arrow `→` between them.

Internal dialog state gains:
- `DateTime? selectedDate` (existing, renamed for clarity — was already `selectedDate`)
- `DateTime? latestDate` (NEW)
- `bool fetchLast50` (existing)

### From chip

- Always tappable
- Label: formatted `yyyy-MM-dd` when set; "Any date" placeholder when null
- Shows a clear `IconButton` (✕) when a date is set
- Clearing the From chip also clears `latestDate`

### To chip

- Disabled (`IgnorePointer` + `Opacity(0.4)`) when `selectedDate == null`
- Label: formatted `yyyy-MM-dd` when set; "No end date" placeholder when null
- Shows a clear `IconButton` (✕) when a date is set
- Date picker `firstDate` is set to `selectedDate` (cannot pick a date before From)
- `lastDate` is `DateTime.now()`

### Fetch last 50 checkbox

When `fetchLast50 == true`, the entire chip row is hidden (same as the current behaviour where the `ListTile` disappears). Both `selectedDate` and `latestDate` are cleared when the checkbox is ticked.

### Dialog states

| State | From chip | To chip |
|---|---|---|
| No dates selected | "Any date" (placeholder) | "No end date" (greyed, disabled) |
| From set, no To | Date value + ✕ | "No end date" (active, tappable) |
| Both set | Date value + ✕ | Date value + ✕ |
| Fetch last 50 checked | Hidden | Hidden |

### Sync button result

```dart
SyncOptions(
  earliestDate: fetchLast50 ? null : selectedDate,
  latestDate: fetchLast50 ? null : latestDate,
  maxEmails: fetchLast50 ? 50 : null,
)
```

---

## Error Handling

No new error states. The date pickers use Flutter's built-in `showDatePicker` which handles invalid input. Constraints:
- From picker: `firstDate: DateTime(2000)`, `lastDate: DateTime.now()`
- To picker: `firstDate: selectedDate`, `lastDate: DateTime.now()`

If the user somehow has a `latestDate` before `earliestDate` (not possible through normal UI flow), the server handles it gracefully — `latestEmailDate` is simply ignored when unparseable or before `earliestEmailDate`.

---

## Testing

Widget tests in `test/utils/dialogs/sync_options_dialog_test.dart`:

1. From chip shows "Any date" placeholder initially
2. To chip is non-interactive (IgnorePointer) when no From date is set
3. Tapping From chip opens date picker; selecting a date updates the From chip label
4. To chip becomes tappable after From is set
5. Tapping To chip opens date picker; selecting a date updates the To chip label
6. Clearing From clears both From and To
7. Checking "Fetch last 50" hides the chip row
8. Sync button returns `SyncOptions` with correct `earliestDate`, `latestDate`, `maxEmails`
