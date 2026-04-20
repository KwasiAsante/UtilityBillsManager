# Responsive Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Utility Bills Manager UI responsive across all six platforms using a single compact/wide breakpoint at 600dp, leaving the phone experience entirely unchanged.

**Architecture:** Add two small utility classes (`AppBreakpoints`, `ResponsiveConstraint`), switch `MainTabScreen` from `NavigationBar` to `NavigationRail` on wide screens, restructure each list screen's AppBar actions to move secondary actions into a ⋮ overflow menu, and make the due-date filter sheet and Assign Bills/Rentor dialogs adaptive.

**Tech Stack:** Flutter (Material 3), `MediaQuery.sizeOf`, `NavigationRail`, `PopupMenuButton`, `showModalBottomSheet`, `showDialog`, `ConstrainedBox`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/utils/app_breakpoints.dart` | **Create** | Single `isWide(context)` helper |
| `lib/widgets/responsive_constraint.dart` | **Create** | Max-width centering wrapper for wide screens |
| `lib/screens/main_tab_screen.dart` | **Modify** | NavigationRail on wide, BottomNav on compact |
| `lib/screens/bills/bill_list_screen.dart` | **Modify** | AppBar restructure + ResponsiveConstraint on body |
| `lib/screens/rentors/rentor_list_screen.dart` | **Modify** | AppBar restructure + ResponsiveConstraint on body |
| `lib/screens/payments/payment_list_screen.dart` | **Modify** | AppBar restructure + ResponsiveConstraint on body |
| `lib/screens/emails/email_list_screen.dart` | **Modify** | AppBar restructure + ResponsiveConstraint on body |
| `lib/screens/summary/summary_screen.dart` | **Modify** | AppBar restructure + ResponsiveConstraint on body |
| `lib/screens/bills/add_edit_bill_screen.dart` | **Modify** | Wrap body in ResponsiveConstraint(maxWidth: 560) |
| `lib/screens/rentors/add_edit_rentor_screen.dart` | **Modify** | Wrap body in ResponsiveConstraint(maxWidth: 560) |
| `lib/screens/payments/add_edit_payment_screen.dart` | **Modify** | Wrap body + adaptive Assign Bills / Assign Rentor |
| `lib/screens/emails/edit_email_data_screen.dart` | **Modify** | Wrap body in ResponsiveConstraint(maxWidth: 560) |
| `lib/screens/settings/settings_screen.dart` | **Modify** | Wrap body in ResponsiveConstraint(maxWidth: 560) |
| `lib/screens/settings/app_config_screen.dart` | **Modify** | Wrap body in ResponsiveConstraint(maxWidth: 560) |
| `lib/screens/settings/server_config_screen.dart` | **Modify** | Wrap body in ResponsiveConstraint(maxWidth: 560) |
| `lib/utils/dialogs/due_date_filter_sheet.dart` | **Modify** | `showDialog` on wide, `showModalBottomSheet` on compact |
| `test/responsive_test.dart` | **Create** | Widget tests for AppBreakpoints + ResponsiveConstraint |

---

## Task 1: AppBreakpoints utility

**Files:**
- Create: `lib/utils/app_breakpoints.dart`
- Create: `test/responsive_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/responsive_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/app_breakpoints.dart';

void main() {
  group('AppBreakpoints', () {
    testWidgets('isWide returns false when width < 600', (tester) async {
      tester.view.physicalSize = const Size(599, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = AppBreakpoints.isWide(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, isFalse);
    });

    testWidgets('isWide returns true when width >= 600', (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = AppBreakpoints.isWide(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/responsive_test.dart
```

Expected: compilation error — `AppBreakpoints` not found.

- [ ] **Step 3: Create the utility class**

```dart
// lib/utils/app_breakpoints.dart
import 'package:flutter/material.dart';

/// Single-breakpoint helper used throughout the app.
///
/// Compact: < 600dp  — phone portrait, small phone landscape
/// Wide:   ≥ 600dp  — tablet, phone landscape, desktop, web
class AppBreakpoints {
  AppBreakpoints._();

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/responsive_test.dart
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/app_breakpoints.dart test/responsive_test.dart
git commit -m "feat: add AppBreakpoints utility for 600dp breakpoint"
```

---

## Task 2: ResponsiveConstraint widget

**Files:**
- Create: `lib/widgets/responsive_constraint.dart`
- Modify: `test/responsive_test.dart`

- [ ] **Step 1: Write failing test**

Add to the bottom of `test/responsive_test.dart`:

```dart
import 'package:utility_bills_manager/widgets/responsive_constraint.dart';

// Add inside main():
  group('ResponsiveConstraint', () {
    testWidgets('passes child through on compact', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveConstraint(
              child: SizedBox(key: Key('inner'), width: 500, height: 100),
            ),
          ),
        ),
      );
      // On compact, no ConstrainedBox wrapping — child renders directly
      expect(find.byKey(const Key('inner')), findsOneWidget);
      expect(find.byType(ConstrainedBox), findsNothing);
    });

    testWidgets('wraps child in ConstrainedBox on wide', (tester) async {
      tester.view.physicalSize = const Size(800, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveConstraint(
              child: SizedBox(key: Key('inner'), width: 500, height: 100),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('inner')), findsOneWidget);
      expect(find.byType(ConstrainedBox), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/responsive_test.dart
```

Expected: compilation error — `ResponsiveConstraint` not found.

- [ ] **Step 3: Create the widget**

```dart
// lib/widgets/responsive_constraint.dart
import 'package:flutter/material.dart';
import '../utils/app_breakpoints.dart';

/// Constrains [child] to [maxWidth] and centres it horizontally on wide screens.
///
/// On compact (< 600dp) screens [child] is returned unchanged.
/// Use [maxWidth] 720 for list screens and 560 for form/settings screens.
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

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/responsive_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/responsive_constraint.dart test/responsive_test.dart
git commit -m "feat: add ResponsiveConstraint widget for max-width centering on wide screens"
```

---

## Task 3: MainTabScreen — NavigationRail on wide

**Files:**
- Modify: `lib/screens/main_tab_screen.dart`

The current `build` method returns a `Scaffold` with `NavigationBar` at the bottom and `IndexedStack` as body. On wide screens, replace the `NavigationBar` with a `NavigationRail` (extended, pinned left) and put a Settings entry at the bottom of the rail via `trailing`. On compact, behavior is identical to today.

- [ ] **Step 1: Add imports and replace the build method**

Open `lib/screens/main_tab_screen.dart`. Replace the entire `build` method:

```dart
@override
Widget build(BuildContext context) {
  final screens = <Widget>[
    BillListScreen(isVisible: _selectedIndex == 0),
    const RentorListScreen(),
    SummaryScreen(isVisible: _selectedIndex == 2),
    PaymentListScreen(isVisible: _selectedIndex == 3),
    EmailListScreen(isVisible: _selectedIndex == 4),
  ];

  final wide = AppBreakpoints.isWide(context);

  if (wide) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.receipt_outlined),
                selectedIcon: Icon(Icons.receipt),
                label: Text('Bills'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('Rentors'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.summarize_outlined),
                selectedIcon: Icon(Icons.summarize),
                label: Text('Summary'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.payment_outlined),
                selectedIcon: Icon(Icons.payment),
                label: Text('Payments'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.email_outlined),
                selectedIcon: Icon(Icons.email),
                label: Text('Emails'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.pushNamed(context, '/settings'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.settings_outlined),
                              SizedBox(width: 24),
                              Text('Settings'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: screens,
            ),
          ),
        ],
      ),
    );
  }

  return Scaffold(
    body: IndexedStack(index: _selectedIndex, children: screens),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onItemTapped,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.receipt_outlined),
          selectedIcon: Icon(Icons.receipt),
          label: 'Bills',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Rentors',
        ),
        NavigationDestination(
          icon: Icon(Icons.summarize_outlined),
          selectedIcon: Icon(Icons.summarize),
          label: 'Summary',
        ),
        NavigationDestination(
          icon: Icon(Icons.payment_outlined),
          selectedIcon: Icon(Icons.payment),
          label: 'Payments',
        ),
        NavigationDestination(
          icon: Icon(Icons.email_outlined),
          selectedIcon: Icon(Icons.email),
          label: 'Emails',
        ),
      ],
    ),
  );
}
```

- [ ] **Step 2: Add the AppBreakpoints import at the top of the file**

Add after the existing imports:

```dart
import '../utils/app_breakpoints.dart';
```

- [ ] **Step 3: Check the Settings route**

Verify `/settings` is registered in your app's router. Search for it:

```bash
grep -r "'/settings'" lib/
```

If the route is registered, proceed. If not, replace `Navigator.pushNamed(context, '/settings')` with the direct push your app uses, e.g.:

```dart
Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
```

Add the SettingsScreen import if needed:
```dart
import 'settings/settings_screen.dart';
```

- [ ] **Step 4: Run the app and verify**

```bash
flutter run
```

On a phone-sized window: bottom navigation bar visible, rail absent.
On a 600dp+ window (tablet/desktop/web): navigation rail on left with all 5 destinations + Settings at bottom; body content on right.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/main_tab_screen.dart
git commit -m "feat: add NavigationRail for wide screens in MainTabScreen"
```

---

## Task 4: BillListScreen AppBar restructure + ResponsiveConstraint

**Files:**
- Modify: `lib/screens/bills/bill_list_screen.dart`

**Current AppBar actions** (lines ~372–459):
- `NotificationBellIcon`
- Google web action (conditional)
- Calendar date filter button
- `filter_alt_off` clear filter button (conditional — when date filter is active)
- Search clear button (conditional)
- Filter `PopupMenuButton` (All/Paid/Unpaid)
- Sort `PopupMenuButton`
- Refresh `IconButton`
- Delete sweep `IconButton`
- `SizedBox(width: 16)` spacer
- `SettingsIconButton`

**Target AppBar actions:**
- `NotificationBellIcon`
- Google web action (conditional)
- Calendar date filter button (the `filter_alt_off` icon is removed; "Clear All" already exists inside the filter sheet)
- Filter `PopupMenuButton`
- Sort `PopupMenuButton`
- ⋮ `PopupMenuButton` containing: Refresh, Settings (compact only), Delete All

Also wrap the `body:` in `ResponsiveConstraint(maxWidth: 720)`.

- [ ] **Step 1: Add imports at the top of bill_list_screen.dart**

```dart
import '../../utils/app_breakpoints.dart';
import '../../widgets/responsive_constraint.dart';
```

- [ ] **Step 2: Replace the AppBar actions**

Find the `actions: [` block inside the `AppBar` in `build` (around line 372). Replace the entire actions list with:

```dart
actions: [
  const NotificationBellIcon(),
  if (isGoogleSignInEnabled)
    googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
  IconButton(
    tooltip: _buildDueDateFilterTooltip(),
    icon: Icon(
      _hasActiveDueDateFilter
          ? Icons.calendar_month
          : Icons.calendar_month_outlined,
    ),
    onPressed: _openDueDateFilterSheet,
  ),
  PopupMenuButton<String>(
    icon: Icon(
      _selectedFilter == 'All'
          ? Icons.filter_list
          : Icons.filter_list_alt,
    ),
    tooltip: 'Filter: $_selectedFilter',
    onSelected: (value) {
      setState(() => _selectedFilter = value);
      _updateDisplayedBills();
    },
    itemBuilder: (context) => ['All', 'Paid', 'Unpaid']
        .map((value) => CheckedPopupMenuItem<String>(
              value: value,
              checked: _selectedFilter == value,
              child: Text(value),
            ))
        .toList(),
  ),
  PopupMenuButton<String>(
    icon: const Icon(Icons.sort),
    tooltip: 'Sort: $_selectedSort',
    onSelected: (value) {
      setState(() => _selectedSort = value);
      _updateDisplayedBills();
    },
    itemBuilder: (context) => [
      'Due Date (Earliest)',
      'Due Date (Latest)',
      'Amount (Lowest)',
      'Amount (Highest)',
    ]
        .map((value) => CheckedPopupMenuItem<String>(
              value: value,
              checked: _selectedSort == value,
              child: Text(value),
            ))
        .toList(),
  ),
  PopupMenuButton<Object>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'More actions',
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: 'refresh',
        child: ListTile(
          leading: Icon(Icons.refresh),
          title: Text('Refresh'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (!AppBreakpoints.isWide(context))
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: 'delete_all',
        child: ListTile(
          leading: Icon(Icons.delete_sweep, color: Colors.red),
          title: Text('Delete all bills',
              style: TextStyle(color: Colors.red)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
    onSelected: (value) {
      if (value == 'refresh') {
        if (!_loading) _syncBills();
      } else if (value == 'settings') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      } else if (value == 'delete_all') {
        _deleteAllBills();
      }
    },
  ),
],
```

- [ ] **Step 3: Remove the SettingsIconButton import if no longer used elsewhere in this file**

Search for other uses of `SettingsIconButton` in `bill_list_screen.dart`:

```bash
grep -n "SettingsIconButton" lib/screens/bills/bill_list_screen.dart
```

If only one occurrence remains (around line 709 in the build method's second `AppBar` if there's a secondary one), remove it too. If there is a second `AppBar` building for a different state (e.g., selection mode), remove `SettingsIconButton` from that one as well and add Settings to its ⋮ menu following the same pattern.

- [ ] **Step 4: Add SettingsScreen import if not already present**

```dart
import '../settings/settings_screen.dart';
```

- [ ] **Step 5: Wrap the body in ResponsiveConstraint**

Find `body: Column(` in the `Scaffold` and wrap it:

```dart
body: ResponsiveConstraint(
  child: Column(
    // ... existing column content unchanged ...
  ),
),
```

- [ ] **Step 6: Run the app and verify**

```bash
flutter run
```

Compact: NotificationBellIcon + calendar + filter + sort + ⋮ visible. ⋮ shows Refresh, Settings, Delete All.
Wide: Same but ⋮ shows only Refresh and Delete All (Settings is in the rail). Body content is centered and max 720dp wide.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/bills/bill_list_screen.dart
git commit -m "feat: restructure BillListScreen AppBar actions and add ResponsiveConstraint"
```

---

## Task 5: RentorListScreen AppBar restructure + ResponsiveConstraint

**Files:**
- Modify: `lib/screens/rentors/rentor_list_screen.dart`

**Current AppBar actions** (lines ~168–213):
- `NotificationBellIcon`
- Search clear (conditional)
- Refresh `IconButton`
- Delete sweep `IconButton`
- `SizedBox(width: 16)`
- Sort `PopupMenuButton`
- `SizedBox(width: 16)`
- `SettingsIconButton`

**Target:**
- `NotificationBellIcon`
- Sort `PopupMenuButton`
- ⋮ `PopupMenuButton`: Refresh, Settings (compact only), Delete All

- [ ] **Step 1: Add imports**

```dart
import '../../utils/app_breakpoints.dart';
import '../../widgets/responsive_constraint.dart';
import '../settings/settings_screen.dart';
```

- [ ] **Step 2: Replace AppBar actions**

```dart
actions: [
  const NotificationBellIcon(),
  PopupMenuButton<String>(
    icon: const Icon(Icons.sort),
    tooltip: 'Sort: $_selectedSort',
    onSelected: (value) {
      setState(() => _selectedSort = value);
      _updateDisplayedRentors();
    },
    itemBuilder: (context) => [
      'Percentage',
      'Last Payment Date (Asc)',
      'Last Payment Date (Desc)',
    ]
        .map((value) => CheckedPopupMenuItem<String>(
              value: value,
              checked: _selectedSort == value,
              child: Text(value),
            ))
        .toList(),
  ),
  PopupMenuButton<Object>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'More actions',
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: 'refresh',
        child: ListTile(
          leading: Icon(Icons.refresh),
          title: Text('Refresh'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (!AppBreakpoints.isWide(context))
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: 'delete_all',
        child: ListTile(
          leading: Icon(Icons.delete_sweep, color: Colors.red),
          title: Text('Delete all rentors',
              style: TextStyle(color: Colors.red)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
    onSelected: (value) async {
      if (value == 'refresh') {
        await _rentorsRepository.reload();
      } else if (value == 'settings') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      } else if (value == 'delete_all') {
        _deleteAllRentors();
      }
    },
  ),
],
```

- [ ] **Step 3: Wrap body in ResponsiveConstraint**

```dart
body: ResponsiveConstraint(
  child: /* existing body widget */,
),
```

The existing `body` starts with either a `_loading ? ...` ternary or `FutureBuilder`. Wrap that entire expression:

```dart
body: ResponsiveConstraint(
  child: _loading
      ? const Center(child: CircularProgressIndicator())
      : FutureBuilder<List<Rentor>>(
          // ... existing unchanged ...
        ),
),
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/rentors/rentor_list_screen.dart
git commit -m "feat: restructure RentorListScreen AppBar actions and add ResponsiveConstraint"
```

---

## Task 6: PaymentListScreen AppBar restructure + ResponsiveConstraint

**Files:**
- Modify: `lib/screens/payments/payment_list_screen.dart`

**Current AppBar actions** (lines ~350–421):
- `NotificationBellIcon`
- Google web action (conditional)
- Calendar date filter button
- `filter_alt_off` clear filter button (conditional)
- Search clear (conditional)
- `SizedBox(width: 16)`
- Sort `PopupMenuButton`
- Refresh `IconButton`
- Delete sweep `IconButton`
- `SizedBox(width: 16)`
- `SettingsIconButton`

**Target:**
- `NotificationBellIcon`
- Google web action (conditional)
- Calendar date filter button (remove `filter_alt_off`)
- Sort `PopupMenuButton`
- ⋮ `PopupMenuButton`: Refresh, Settings (compact only), Delete All

- [ ] **Step 1: Add imports**

```dart
import '../../utils/app_breakpoints.dart';
import '../../widgets/responsive_constraint.dart';
import '../settings/settings_screen.dart';
```

- [ ] **Step 2: Replace AppBar actions**

```dart
actions: [
  const NotificationBellIcon(),
  if (isGoogleSignInEnabled)
    googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
  IconButton(
    tooltip: _buildPaymentDateFilterTooltip(),
    icon: Icon(
      _hasActivePaymentDateFilter
          ? Icons.calendar_month
          : Icons.calendar_month_outlined,
    ),
    onPressed: _openPaymentDateFilterSheet,
  ),
  PopupMenuButton<String>(
    icon: const Icon(Icons.sort),
    tooltip: 'Sort: $_selectedSort',
    onSelected: (value) {
      setState(() => _selectedSort = value);
      _updateDisplayedPayments();
    },
    itemBuilder: (context) => [
      'Payment Date (Earliest)',
      'Payment Date (Latest)',
      'Amount Paid (Lowest)',
      'Amount Paid (Highest)',
    ]
        .map((value) => CheckedPopupMenuItem<String>(
              value: value,
              checked: _selectedSort == value,
              child: Text(value),
            ))
        .toList(),
  ),
  PopupMenuButton<Object>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'More actions',
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: 'refresh',
        child: ListTile(
          leading: Icon(Icons.refresh),
          title: Text('Refresh'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (!AppBreakpoints.isWide(context))
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: 'delete_all',
        child: ListTile(
          leading: Icon(Icons.delete_sweep, color: Colors.red),
          title: Text('Delete all payments',
              style: TextStyle(color: Colors.red)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
    onSelected: (value) async {
      if (value == 'refresh') {
        await _syncPayments();
      } else if (value == 'settings') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      } else if (value == 'delete_all') {
        _deleteAllPayments();
      }
    },
  ),
],
```

- [ ] **Step 3: Wrap body in ResponsiveConstraint**

```dart
body: ResponsiveConstraint(
  child: Column(
    // ... existing column content unchanged ...
  ),
),
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/payments/payment_list_screen.dart
git commit -m "feat: restructure PaymentListScreen AppBar actions and add ResponsiveConstraint"
```

---

## Task 7: EmailListScreen AppBar restructure + ResponsiveConstraint

**Files:**
- Modify: `lib/screens/emails/email_list_screen.dart`

**Current AppBar actions** (lines ~264–331):
- `NotificationBellIcon`
- Google web action (conditional)
- Search clear (conditional)
- Filter `PopupMenuButton` (All/Processed/Unprocessed)
- Sort `PopupMenuButton`
- Refresh `IconButton`
- Delete sweep `IconButton`
- `SizedBox(width: 16)`
- `SettingsIconButton`

**Target:**
- `NotificationBellIcon`
- Google web action (conditional)
- Filter `PopupMenuButton`
- Sort `PopupMenuButton`
- ⋮ `PopupMenuButton`: Refresh, Settings (compact only), Delete All

- [ ] **Step 1: Add imports**

```dart
import '../../utils/app_breakpoints.dart';
import '../../widgets/responsive_constraint.dart';
import '../settings/settings_screen.dart';
```

- [ ] **Step 2: Replace AppBar actions**

```dart
actions: [
  const NotificationBellIcon(),
  if (isGoogleSignInEnabled)
    googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
  PopupMenuButton<String>(
    icon: Icon(
      _selectedFilter == 'All'
          ? Icons.filter_list
          : Icons.filter_list_alt,
    ),
    tooltip: 'Filter: $_selectedFilter',
    onSelected: (value) {
      setState(() => _selectedFilter = value);
      _updateDisplayedEmails();
    },
    itemBuilder: (context) => ['All', 'Processed', 'Unprocessed']
        .map((value) => CheckedPopupMenuItem<String>(
              value: value,
              checked: _selectedFilter == value,
              child: Text(value),
            ))
        .toList(),
  ),
  PopupMenuButton<String>(
    icon: const Icon(Icons.sort),
    tooltip: 'Sort: $_selectedSort',
    onSelected: (value) {
      setState(() => _selectedSort = value);
      _updateDisplayedEmails();
    },
    itemBuilder: (context) => [
      'Default',
      'Subject (A-Z)',
      'Subject (Z-A)',
      'Processed First',
      'Unprocessed First',
    ]
        .map((value) => CheckedPopupMenuItem<String>(
              value: value,
              checked: _selectedSort == value,
              child: Text(value),
            ))
        .toList(),
  ),
  PopupMenuButton<Object>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'More actions',
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: 'refresh',
        child: ListTile(
          leading: Icon(Icons.refresh),
          title: Text('Sync emails'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (!AppBreakpoints.isWide(context))
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: 'delete_all',
        child: ListTile(
          leading: Icon(Icons.delete_sweep, color: Colors.red),
          title: Text('Delete all email records',
              style: TextStyle(color: Colors.red)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
    onSelected: (value) {
      if (value == 'refresh') {
        _syncEmails();
      } else if (value == 'settings') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      } else if (value == 'delete_all') {
        _deleteAllEmails();
      }
    },
  ),
],
```

- [ ] **Step 3: Wrap body in ResponsiveConstraint**

```dart
body: ResponsiveConstraint(
  child: Column(
    // ... existing column content unchanged ...
  ),
),
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/emails/email_list_screen.dart
git commit -m "feat: restructure EmailListScreen AppBar actions and add ResponsiveConstraint"
```

---

## Task 8: SummaryScreen AppBar restructure + ResponsiveConstraint

**Files:**
- Modify: `lib/screens/summary/summary_screen.dart`

**Current AppBar actions** (lines ~662–710):
- `NotificationBellIcon`
- Google web action (conditional)
- Sync `IconButton` (`Icons.sync`)
- Filter `PopupMenuButton` (All/Paid/Unpaid)
- Visibility toggle `IconButton`
- CSV export `IconButton`
- PDF export `IconButton`
- Delete All Data `IconButton` (red)
- `SizedBox(width: 16)`
- `SettingsIconButton`

**Target:**
- `NotificationBellIcon`
- Google web action (conditional)
- Filter `PopupMenuButton`
- ⋮ `PopupMenuButton`: Sync, Show/Hide actual unpaid, Export CSV, Export PDF, Settings (compact only), Delete All Data

- [ ] **Step 1: Add imports**

```dart
import '../../utils/app_breakpoints.dart';
import '../../widgets/responsive_constraint.dart';
import '../settings/settings_screen.dart';
```

- [ ] **Step 2: Replace AppBar actions**

```dart
actions: [
  const NotificationBellIcon(),
  if (isGoogleSignInEnabled)
    googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
  PopupMenuButton<String>(
    icon: Icon(
      _statusFilter == 'All' ? Icons.filter_list : Icons.filter_list_alt,
    ),
    tooltip: 'Filter: $_statusFilter',
    onSelected: (value) => setState(() => _statusFilter = value),
    itemBuilder: (context) => ['All', 'Paid', 'Unpaid']
        .map((value) => CheckedPopupMenuItem<String>(
              value: value,
              checked: _statusFilter == value,
              child: Text(value),
            ))
        .toList(),
  ),
  PopupMenuButton<Object>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'More actions',
    itemBuilder: (context) => [
      PopupMenuItem(
        value: 'sync',
        enabled: !_loading,
        child: const ListTile(
          leading: Icon(Icons.sync),
          title: Text('Sync bills & payments'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'toggle_unpaid',
        child: ListTile(
          leading: Icon(
            _showActualUnpaid ? Icons.visibility : Icons.visibility_off,
          ),
          title: Text(
            _showActualUnpaid
                ? 'Hide actual unpaid amounts'
                : 'Show actual unpaid amounts',
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: 'export_csv',
        child: ListTile(
          leading: Icon(Icons.table_chart_outlined),
          title: Text('Export CSV'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: 'export_pdf',
        child: ListTile(
          leading: Icon(Icons.picture_as_pdf_outlined),
          title: Text('Export PDF'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (!AppBreakpoints.isWide(context))
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: 'delete_all',
        child: ListTile(
          leading: Icon(Icons.delete_forever, color: Colors.red),
          title: Text('Delete All Data',
              style: TextStyle(color: Colors.red)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
    onSelected: (value) {
      if (value == 'sync') {
        if (!_loading) _syncData();
      } else if (value == 'toggle_unpaid') {
        setState(() => _showActualUnpaid = !_showActualUnpaid);
      } else if (value == 'export_csv') {
        _exportToCSV();
      } else if (value == 'export_pdf') {
        _exportToPDF();
      } else if (value == 'settings') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      } else if (value == 'delete_all') {
        _deleteAllData();
      }
    },
  ),
],
```

- [ ] **Step 3: Wrap body in ResponsiveConstraint**

```dart
body: ResponsiveConstraint(
  child: Column(
    // ... existing column content unchanged ...
  ),
),
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/summary/summary_screen.dart
git commit -m "feat: restructure SummaryScreen AppBar actions and add ResponsiveConstraint"
```

---

## Task 9: Form screens — ResponsiveConstraint (maxWidth: 560)

**Files:**
- Modify: `lib/screens/bills/add_edit_bill_screen.dart`
- Modify: `lib/screens/rentors/add_edit_rentor_screen.dart`
- Modify: `lib/screens/payments/add_edit_payment_screen.dart`
- Modify: `lib/screens/emails/edit_email_data_screen.dart`

These screens all have `Scaffold(body: SingleChildScrollView(...))` or similar. Add `ResponsiveConstraint(maxWidth: 560)` wrapping each `body:` value. No AppBar changes needed here.

- [ ] **Step 1: AddEditBillScreen**

Open `lib/screens/bills/add_edit_bill_screen.dart`.

Add import:
```dart
import '../../widgets/responsive_constraint.dart';
```

Find the `body:` in the `Scaffold` and wrap the value:
```dart
body: ResponsiveConstraint(
  maxWidth: 560,
  child: SingleChildScrollView(/* existing unchanged */),
),
```

- [ ] **Step 2: AddEditRentorScreen**

Open `lib/screens/rentors/add_edit_rentor_screen.dart`.

Add import:
```dart
import '../../widgets/responsive_constraint.dart';
```

Wrap the `body:` value:
```dart
body: ResponsiveConstraint(
  maxWidth: 560,
  child: SingleChildScrollView(/* existing unchanged */),
),
```

- [ ] **Step 3: EditEmailDataScreen**

Open `lib/screens/emails/edit_email_data_screen.dart`.

Add import:
```dart
import '../../widgets/responsive_constraint.dart';
```

Wrap the `body:` value:
```dart
body: ResponsiveConstraint(
  maxWidth: 560,
  child: /* existing body widget */,
),
```

- [ ] **Step 4: AddEditPaymentScreen — body only (dialogs handled in Task 12)**

Open `lib/screens/payments/add_edit_payment_screen.dart`.

Add import (will also be needed in Task 12):
```dart
import '../../widgets/responsive_constraint.dart';
import '../../utils/app_breakpoints.dart';
```

Wrap the `body:` value:
```dart
body: ResponsiveConstraint(
  maxWidth: 560,
  child: SingleChildScrollView(/* existing unchanged */),
),
```

- [ ] **Step 5: Run the app and verify forms**

```bash
flutter run
```

On a wide screen, all form screens should have content centred and constrained to 560dp. On compact, forms look identical to before.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/bills/add_edit_bill_screen.dart \
        lib/screens/rentors/add_edit_rentor_screen.dart \
        lib/screens/payments/add_edit_payment_screen.dart \
        lib/screens/emails/edit_email_data_screen.dart
git commit -m "feat: add ResponsiveConstraint to form screens (maxWidth 560)"
```

---

## Task 10: Settings screens — ResponsiveConstraint (maxWidth: 560)

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`
- Modify: `lib/screens/settings/app_config_screen.dart`
- Modify: `lib/screens/settings/server_config_screen.dart`

Same pattern as Task 9.

- [ ] **Step 1: SettingsScreen**

Open `lib/screens/settings/settings_screen.dart`.

Add import:
```dart
import '../../widgets/responsive_constraint.dart';
```

Wrap the `body:`:
```dart
body: ResponsiveConstraint(
  maxWidth: 560,
  child: /* existing body widget */,
),
```

- [ ] **Step 2: AppConfigScreen**

Open `lib/screens/settings/app_config_screen.dart`.

Add import:
```dart
import '../../widgets/responsive_constraint.dart';
```

Wrap the `body:`:
```dart
body: ResponsiveConstraint(
  maxWidth: 560,
  child: /* existing body widget */,
),
```

- [ ] **Step 3: ServerConfigScreen**

Open `lib/screens/settings/server_config_screen.dart`.

Add import:
```dart
import '../../widgets/responsive_constraint.dart';
```

Wrap the `body:`:
```dart
body: ResponsiveConstraint(
  maxWidth: 560,
  child: /* existing body widget */,
),
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings/settings_screen.dart \
        lib/screens/settings/app_config_screen.dart \
        lib/screens/settings/server_config_screen.dart
git commit -m "feat: add ResponsiveConstraint to settings screens (maxWidth 560)"
```

---

## Task 11: DueDateFilterSheet — adaptive (dialog on wide, sheet on compact)

**Files:**
- Modify: `lib/utils/dialogs/due_date_filter_sheet.dart`

**Current:** `DueDateFilterSheet.show()` always calls `showModalBottomSheet`.

**Target:** On wide (≥ 600dp) call `showDialog` with `maxWidth: 420` and a `Dialog` wrapper; on compact keep `showModalBottomSheet`.

The content widget `_DueDateFilterSheetContent` is already extracted — it is reused as-is in both cases.

- [ ] **Step 1: Add import**

```dart
import '../app_breakpoints.dart';
```

- [ ] **Step 2: Replace the `show` static method**

```dart
static Future<DueDateFilterResult?> show(
  BuildContext context, {
  required List<int> availableYears,
  DueDateFilterResult current = const DueDateFilterResult(),
}) {
  final content = _DueDateFilterSheetContent(
    availableYears: availableYears,
    current: current,
    monthNames: AppConstants.monthNames,
    formatDate: formatDate,
    constrainedFirst: _constrainedFirst,
    constrainedLast: _constrainedLast,
  );

  if (AppBreakpoints.isWide(context)) {
    return showDialog<DueDateFilterResult>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(child: content),
        ),
      ),
    );
  }

  return showModalBottomSheet<DueDateFilterResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => content,
  );
}
```

Note: `ConstrainedBox` requires `import 'package:flutter/material.dart';` — already present.

- [ ] **Step 3: Verify the app runs**

```bash
flutter run
```

On compact: tap the calendar icon → bottom sheet slides up as before.
On wide (600dp+): tap the calendar icon → centred dialog appears.

- [ ] **Step 4: Commit**

```bash
git add lib/utils/dialogs/due_date_filter_sheet.dart
git commit -m "feat: make DueDateFilterSheet adaptive — dialog on wide, sheet on compact"
```

---

## Task 12: AddEditPaymentScreen — adaptive Assign Bills and Assign Rentor

**Files:**
- Modify: `lib/screens/payments/add_edit_payment_screen.dart`

**Current:** `_showBillSelectionDialog()` and `_showRentorPickerDialog()` both call `showDialog`. On compact they should call `showModalBottomSheet` instead; on wide they keep `showDialog`.

`_BillSelectionDialog` (line 665) and `_RentorPickerDialog` (line 473) each return `AlertDialog`. The strategy: extract the dialog _content_ from each `AlertDialog` into a new private content widget, then in each show method check `AppBreakpoints.isWide`.

### Assign Rentor

- [ ] **Step 1: Extract `_RentorPickerContent`**

`_RentorPickerDialogState.build` at line 538 returns `AlertDialog(title: ..., content: SingleChildScrollView(...), actions: [...])`.

Rename `_RentorPickerDialog` → `_RentorPickerContent` and `_RentorPickerDialogState` → `_RentorPickerContentState`. Change `build` to return a `Column` instead of `AlertDialog`:

```dart
class _RentorPickerContent extends StatefulWidget {
  final Rentor? currentSelectedRentor;
  final Function(Rentor?, List<Rentor>) onAdd;
  final List<Rentor> allRentors;
  final RentorsHelper rentorsHelper;

  const _RentorPickerContent({
    required this.currentSelectedRentor,
    required this.allRentors,
    required this.rentorsHelper,
    required this.onAdd,
  });

  @override
  State<_RentorPickerContent> createState() => _RentorPickerContentState();
}
```

In `_RentorPickerContentState.build`, change the return value from `AlertDialog` to:

```dart
return Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Text(
        'Assign Rentor',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ),
    Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // … same children that were inside the AlertDialog content …
          ],
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // … same actions that were in AlertDialog.actions …
        ],
      ),
    ),
  ],
);
```

> **Tip:** The children and actions come from the existing `AlertDialog` body — copy them exactly.

- [ ] **Step 2: Update `_showRentorPickerDialog` to be adaptive**

```dart
Future<void> _showRentorPickerDialog() async {
  if (_allRentors.isEmpty) {
    final result = await _rentorsHelper.readAllRentors();
    if (!mounted) return;
    if (result.isSuccess) {
      setState(() => _allRentors = result.data!);
    }
  }

  final content = _RentorPickerContent(
    currentSelectedRentor: _selectedRentor,
    allRentors: _allRentors,
    rentorsHelper: _rentorsHelper,
    onAdd: (Rentor? selectedRentor, List<Rentor> allRentors) {
      setState(() {
        _allRentors = allRentors;
        _selectedRentor = selectedRentor;
        if (_selectedRentor == null) {
          _clearRentorSelection();
        } else {
          _rentorController.text = selectedRentor?.name ?? '';
        }
      });
    },
  );

  if (!mounted) return;

  if (AppBreakpoints.isWide(context)) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: content,
        ),
      ),
    );
  } else {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: content,
      ),
    );
  }
}
```

### Assign Bills

- [ ] **Step 3: Extract `_BillSelectionContent`**

`_BillSelectionDialogState.build` at line 866 returns `AlertDialog(...)`.

Apply the same rename pattern: `_BillSelectionDialog` → `_BillSelectionContent`, `_BillSelectionDialogState` → `_BillSelectionContentState`. Change `build` to return a `Column` (same structure as Step 1 above, but for bill selection content).

- [ ] **Step 4: Update `_showBillSelectionDialog` to be adaptive**

```dart
void _showBillSelectionDialog() {
  final paymentDate = _parsePaymentDateForBillFilter();

  final content = _BillSelectionContent(
    currentSelectedBills: _selectedBills,
    allBills: _allBills,
    billsHelper: _billsHelper,
    excludedBillTypes: _selectedRentor?.excludedBillTypes,
    initialDueYear: paymentDate?.year,
    initialDueMonth: paymentDate?.month,
    onAdd: (selectedBills, allBills) {
      setState(() {
        _removeAllBills();
        _selectedBills = selectedBills;
        _allBills = allBills;
        if (_selectedBills.isNotEmpty) {
          _addBills();
        }
      });
    },
  );

  if (AppBreakpoints.isWide(context)) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: content,
        ),
      ),
    );
  } else {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: content,
      ),
    );
  }
}
```

- [ ] **Step 5: Run the app and verify**

```bash
flutter run
```

- Compact: tap "Add" on Bills or Rentor in the payment form → bottom sheet slides up.
- Wide: tap "Add" → centred dialog appears with `maxWidth: 480`.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/payments/add_edit_payment_screen.dart
git commit -m "feat: make Assign Bills and Assign Rentor dialogs adaptive in AddEditPaymentScreen"
```

---

## Self-Review Against Spec

### Spec coverage checklist

| Spec requirement | Covered by task |
|---|---|
| `AppBreakpoints` 600dp helper | Task 1 |
| `ResponsiveConstraint` widget | Task 2 |
| `NavigationRail` on wide in `MainTabScreen` | Task 3 |
| Settings in rail trailing on wide | Task 3 |
| `BillListScreen` AppBar restructure | Task 4 |
| `RentorListScreen` AppBar restructure | Task 5 |
| `PaymentListScreen` AppBar restructure | Task 6 |
| `EmailListScreen` AppBar restructure | Task 7 |
| `SummaryScreen` AppBar restructure | Task 8 |
| `filter_alt_off` icon removed (clear is in sheet) | Tasks 4, 6 |
| Settings in ⋮ on compact, absent in ⋮ on wide | Tasks 4–8 |
| `ResponsiveConstraint(720)` on list screens | Tasks 4–8 |
| `ResponsiveConstraint(560)` on form screens | Task 9 |
| `ResponsiveConstraint(560)` on settings screens | Task 10 |
| Due date filter: dialog on wide, sheet on compact | Task 11 |
| Assign Bills: dialog on wide, sheet on compact | Task 12 |
| Assign Rentor: dialog on wide, sheet on compact | Task 12 |
| Phone (compact) experience unchanged | Verified throughout |

### Gap: Summary screen date filter

The spec states "date filter icon only appears on Bills, Payments, and **Summary**", but `summary_screen.dart` does not currently have a date filter feature. Adding it would require new business logic (filtering the summary data by date range) and is outside the scope of a responsive layout change. This plan restructures the existing Summary AppBar without adding the date filter.

### Gap: `add_edit_rentor_screen.dart` listed in spec files affected

The spec lists `add_edit_rentor_screen.dart` under "ResponsiveConstraint wrapper + Assign Rentor sheet/dialog". The Assign Rentor dialog in that file (`_showAddBillPercentageDialog`) is a simple configuration dialog, not the same "Assign Rentor" as in the payment screen. This plan applies `ResponsiveConstraint` to the body (Task 9) and leaves its internal dialogs unchanged, as they are "simple" dialogs that remain `AlertDialog` on both breakpoints per the spec's dialog rules.
