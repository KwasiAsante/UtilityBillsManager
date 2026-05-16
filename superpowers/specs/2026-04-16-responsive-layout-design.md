# Responsive Layout Design

**Date:** 2026-04-16  
**Status:** Approved  

---

## Overview

Make the Utility Bills Manager UI responsive across its six target platforms (Android, iOS, macOS, Windows, Linux, Web) using a single breakpoint: **compact** (< 600dp) and **wide** (≥ 600dp).

The phone experience is preserved entirely. Changes only activate at ≥ 600dp.

---

## Breakpoints

| Name | Width | Typical context |
|---|---|---|
| Compact | < 600dp | Phone portrait, small phone landscape |
| Wide | ≥ 600dp | Tablet, phone landscape, desktop, web |

A single `AppBreakpoints` utility class exposes this:

```dart
class AppBreakpoints {
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600;
}
```

---

## 1. Navigation (`MainTabScreen`)

### Compact
- Existing `BottomNavigationBar` — **no change**.

### Wide
- Replace `BottomNavigationBar` with a `NavigationRail` pinned to the left side of the screen.
- Rail uses `extended: true` so both icon and label are visible side by side.
- The `SettingsIconButton` moves out of every screen's `AppBar.actions` and into the rail as a trailing widget pinned to the bottom (using `NavigationRail.trailing`).
- The `IndexedStack` body sits to the right of the rail.

### Implementation note
`MainTabScreen` wraps its `Scaffold` body in a `Row`:
- Wide: `NavigationRail` + `Expanded(child: IndexedStack(...))`
- Compact: `IndexedStack(...)` as full body with `BottomNavigationBar`

---

## 2. Content constraint (`ResponsiveConstraint` widget)

A small reusable wrapper applied once per screen — both list screens and form/edit screens.

```dart
class ResponsiveConstraint extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ResponsiveConstraint({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppBreakpoints.isWide(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
```

**Applied to (13 screens):**
- List screens: `BillListScreen`, `RentorListScreen`, `PaymentListScreen`, `EmailListScreen`, `SummaryScreen` — `maxWidth: 720`
- Form/edit screens: `AddEditBillScreen`, `AddEditRentorScreen`, `AddEditPaymentScreen`, `EditEmailDataScreen` — `maxWidth: 560`
- Settings screens: `SettingsScreen`, `AppConfigScreen`, `ServerConfigScreen` — `maxWidth: 560`

---

## 3. AppBar actions

### Compact
Every list screen's `AppBar.actions` is restructured to:

| Position | Widget | Action |
|---|---|---|
| 1 | `NotificationBellIcon` | Notifications |
| 2 | `IconButton` (calendar) | Date filter |
| 3 | `PopupMenuButton` (filter_list) | Filter (All / Paid / Unpaid) |
| 4 | `PopupMenuButton` (sort) | Sort options |
| 5 | `PopupMenuButton` (⋮ more_vert) | Refresh · Settings · Delete All |

The `SettingsIconButton` is **removed** from `AppBar.actions` on all screens — on compact it lives in the ⋮ menu, on wide it lives in the rail.

> **Note:** Not every screen has all 5 primary icons. The date filter icon only appears on Bills, Payments, and Summary. The filter icon only appears on Bills, Emails, and Summary. Each screen's ⋮ menu contains whatever secondary actions apply to that screen (Refresh, Settings, Delete All where relevant).

The conditional `filter_alt_off` clear-filter button (currently shown as an extra icon when a date filter is active) moves inside the date filter popup as a "Clear filter" option rather than an additional icon.

### Wide
- `SettingsIconButton` removed from `AppBar.actions` (it's in the rail).
- Remaining icons stay in actions with `IconButton` using default 48dp tap targets — naturally more spread out with one fewer icon.

---

## 4. Dialogs and sheets

### Rule
| Dialog type | Compact | Wide |
|---|---|---|
| Simple (Sync options, Select Period, Calculate Amount Owed, confirm/delete alerts) | Centred `AlertDialog` — **no change** | Centred `AlertDialog` — **no change** |
| Assign Bills | `showModalBottomSheet` (new) | `showDialog` with `maxWidth: 480` (existing) |
| Assign Rentor | `showModalBottomSheet` (new) | `showDialog` with `maxWidth: 480` (existing) |
| Due date filter sheet | `showModalBottomSheet` — **no change** | `showDialog` with `maxWidth: 420` |

### Implementation pattern
Each affected call site checks `AppBreakpoints.isWide(context)` and calls either `showDialog` or `showModalBottomSheet`. The content widget (the form/list inside the dialog) is extracted into a shared private widget so it is not duplicated.

---

## 5. Settings access

| Breakpoint | Where Settings lives |
|---|---|
| Compact | First item in the ⋮ `PopupMenuButton` in every screen's AppBar |
| Wide | `NavigationRail.trailing` — a `NavigationRailDestination` pinned to the bottom of the rail, separated by a `Divider` |

Tapping Settings navigates to `SettingsScreen` in both cases (same `Navigator.push` call).

---

## 6. What does NOT change

- All card layouts, list item layouts, form field arrangements — untouched.
- The phone (compact) experience is identical to today.
- The overflow fixes already applied (dropdown → `PopupMenuButton`, `isExpanded: true` on dropdowns in `EditEmailDataScreen`) stay as-is.
- No new routes, no new navigation packages.

---

## Files affected

| File | Change |
|---|---|
| `lib/utils/app_breakpoints.dart` | **New** — breakpoint helper |
| `lib/widgets/responsive_constraint.dart` | **New** — max-width centering wrapper |
| `lib/screens/main_tab_screen.dart` | Navigation rail on wide, bottom nav on compact |
| `lib/screens/bills/bill_list_screen.dart` | AppBar actions restructure |
| `lib/screens/rentors/rentor_list_screen.dart` | AppBar actions restructure |
| `lib/screens/payments/payment_list_screen.dart` | AppBar actions restructure |
| `lib/screens/emails/email_list_screen.dart` | AppBar actions restructure |
| `lib/screens/summary/summary_screen.dart` | AppBar actions restructure |
| `lib/screens/bills/add_edit_bill_screen.dart` | `ResponsiveConstraint` wrapper |
| `lib/screens/rentors/add_edit_rentor_screen.dart` | `ResponsiveConstraint` wrapper + Assign Rentor sheet/dialog |
| `lib/screens/payments/add_edit_payment_screen.dart` | `ResponsiveConstraint` wrapper + Assign Bills sheet/dialog |
| `lib/screens/emails/edit_email_data_screen.dart` | `ResponsiveConstraint` wrapper |
| `lib/screens/settings/settings_screen.dart` | `ResponsiveConstraint` wrapper |
| `lib/screens/settings/app_config_screen.dart` | `ResponsiveConstraint` wrapper |
| `lib/screens/settings/server_config_screen.dart` | `ResponsiveConstraint` wrapper |
| `lib/utils/dialogs/due_date_filter_sheet.dart` | `showDialog` on wide, `showModalBottomSheet` on compact |
| `lib/widgets/settings_icon_button.dart` | Remove from AppBar usage; used only in rail |
