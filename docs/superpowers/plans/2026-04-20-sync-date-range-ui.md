# Sync Dialog Date Range UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single "earliest date" ListTile in `SyncOptionsDialog` with an inline "From → To" chip row, and add `latestDate` to `SyncOptions`.

**Architecture:** All changes are confined to `lib/utils/dialogs/sync_options_dialog.dart`. A private `_DateChip` widget is extracted to keep the dialog builder readable. `SyncOptions` gains one new nullable field `latestDate`; all callers are unaffected since it defaults to null (wiring to the API is Task 4).

**Tech Stack:** Flutter widget tests (`flutter_test`), Material date picker

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/utils/dialogs/sync_options_dialog.dart` | Modify | Add `latestDate` to `SyncOptions`; replace ListTile with chip row; extract `_DateChip` |
| `test/utils/dialogs/sync_options_dialog_test.dart` | Create | Widget tests for chip states, disabling, clearing, and return values |

---

### Task 1: Create the feature branch

- [ ] **Step 1: Create and check out the branch**

```bash
git checkout -b feat/sync-date-range-ui
```

- [ ] **Step 2: Verify**

```bash
git branch --show-current
```
Expected: `feat/sync-date-range-ui`

---

### Task 2: Write failing widget tests

- [ ] **Step 1: Create the test directory**

```bash
mkdir -p test/utils/dialogs
```

- [ ] **Step 2: Create `test/utils/dialogs/sync_options_dialog_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/dialogs/sync_options_dialog.dart';

void main() {
  late Future<SyncOptions?> dialogFuture;

  Widget buildApp() {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () {
              dialogFuture = SyncOptionsDialog.show(context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('SyncOptionsDialog initial state', () {
    testWidgets('shows From chip with Any date placeholder', (tester) async {
      await openDialog(tester);
      expect(find.text('Any date'), findsOneWidget);
    });

    testWidgets('shows To chip with No end date placeholder', (tester) async {
      await openDialog(tester);
      expect(find.text('No end date'), findsOneWidget);
    });
  });

  group('SyncOptionsDialog To chip disabled state', () {
    testWidgets('To chip does not open date picker when From is not set',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('No end date'));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsNothing);
    });
  });

  group('SyncOptionsDialog From date selection', () {
    testWidgets(
        'tapping From chip opens date picker and accepting updates label',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Any date'));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Any date'), findsNothing);
    });
  });

  group('SyncOptionsDialog To chip enabled after From set', () {
    testWidgets('To chip opens date picker after From is set', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Any date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No end date'));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('No end date'), findsNothing);
    });
  });

  group('SyncOptionsDialog clearing', () {
    testWidgets('clearing From also clears To', (tester) async {
      await openDialog(tester);
      // Set From
      await tester.tap(find.text('Any date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Set To
      await tester.tap(find.text('No end date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Clear From (first clear icon)
      await tester.tap(find.byIcon(Icons.clear).first);
      await tester.pumpAndSettle();
      expect(find.text('Any date'), findsOneWidget);
      expect(find.text('No end date'), findsOneWidget);
    });
  });

  group('SyncOptionsDialog Fetch last 50', () {
    testWidgets('checking Fetch last 50 hides the date range row',
        (tester) async {
      await openDialog(tester);
      expect(find.text('Any date'), findsOneWidget);
      await tester.tap(find.text('Fetch last 50 emails instead'));
      await tester.pumpAndSettle();
      expect(find.text('Any date'), findsNothing);
      expect(find.text('No end date'), findsNothing);
    });
  });

  group('SyncOptionsDialog return values', () {
    testWidgets('Sync with no dates returns SyncOptions with all nulls',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result, isNotNull);
      expect(result!.earliestDate, isNull);
      expect(result.latestDate, isNull);
      expect(result.maxEmails, isNull);
    });

    testWidgets('Fetch last 50 returns SyncOptions with maxEmails 50',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Fetch last 50 emails instead'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result!.maxEmails, equals(50));
      expect(result.earliestDate, isNull);
      expect(result.latestDate, isNull);
    });

    testWidgets('Cancel returns null', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result, isNull);
    });
  });
}
```

- [ ] **Step 3: Run the tests to confirm they fail**

```bash
flutter test test/utils/dialogs/sync_options_dialog_test.dart
```

Expected: Tests FAIL — `latestDate` field doesn't exist on `SyncOptions`, "Any date" / "No end date" text not found.

---

### Task 3: Implement the changes in `sync_options_dialog.dart`

- [ ] **Step 1: Read the current file**

Read `lib/utils/dialogs/sync_options_dialog.dart` in full before editing.

- [ ] **Step 2: Replace the entire file with the new implementation**

Write the following content to `lib/utils/dialogs/sync_options_dialog.dart`:

```dart
import 'package:flutter/material.dart';

/// Holds the user's selections from [SyncOptionsDialog]: a date range to
/// filter emails and the maximum number of emails to retrieve.
class SyncOptions {
  final DateTime? earliestDate;
  final DateTime? latestDate;
  final int? maxEmails;

  const SyncOptions({this.earliestDate, this.latestDate, this.maxEmails});
}

/// Static-only utility that shows a dialog for configuring email sync options.
///
/// The user can pick a date range (earliest → latest) or tick "Fetch last
/// 50 emails" to ignore the date filter entirely.
class SyncOptionsDialog {
  SyncOptionsDialog._();

  /// Shows the sync-options [AlertDialog] and returns the user's [SyncOptions],
  /// or `null` if the dialog was cancelled.
  static Future<SyncOptions?> show(BuildContext context) {
    DateTime? selectedDate;
    DateTime? latestDate;
    bool fetchLast50 = false;

    return showDialog<SyncOptions>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Sync Emails'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose a date range to fetch emails, or fetch the last 50 emails regardless of date.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (!fetchLast50)
                    Row(
                      children: [
                        Expanded(
                          child: _DateChip(
                            label: 'From',
                            date: selectedDate,
                            placeholder: 'Any date',
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setDialogState(() => selectedDate = date);
                              }
                            },
                            onClear: () => setDialogState(() {
                              selectedDate = null;
                              latestDate = null;
                            }),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '→',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: IgnorePointer(
                            ignoring: selectedDate == null,
                            child: Opacity(
                              opacity: selectedDate == null ? 0.4 : 1.0,
                              child: _DateChip(
                                label: 'To',
                                date: latestDate,
                                placeholder: 'No end date',
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        latestDate ?? selectedDate!,
                                    firstDate: selectedDate!,
                                    lastDate: DateTime.now(),
                                  );
                                  if (date != null) {
                                    setDialogState(() => latestDate = date);
                                  }
                                },
                                onClear: () => setDialogState(
                                  () => latestDate = null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fetch last 50 emails instead'),
                    value: fetchLast50,
                    onChanged: (value) {
                      setDialogState(() {
                        fetchLast50 = value ?? false;
                        if (fetchLast50) {
                          selectedDate = null;
                          latestDate = null;
                        }
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    SyncOptions(
                      earliestDate: fetchLast50 ? null : selectedDate,
                      latestDate: fetchLast50 ? null : latestDate,
                      maxEmails: fetchLast50 ? 50 : null,
                    ),
                  ),
                  child: const Text('Sync'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A compact tappable chip for displaying and selecting a date.
class _DateChip extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateChip({
    required this.label,
    required this.date,
    required this.placeholder,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    date != null
                        ? date!.toLocal().toString().split(' ')[0]
                        : placeholder,
                    style: TextStyle(
                      fontSize: 12,
                      color: date != null
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      fontWeight: date != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontStyle: date != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.clear, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Verify the file compiles**

```bash
flutter analyze lib/utils/dialogs/sync_options_dialog.dart
```
Expected: no errors or warnings.

---

### Task 4: Run tests and commit

- [ ] **Step 1: Run the dialog tests**

```bash
flutter test test/utils/dialogs/sync_options_dialog_test.dart
```
Expected: All 9 tests PASS.

- [ ] **Step 2: Run the full test suite**

```bash
flutter test
```
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/utils/dialogs/sync_options_dialog.dart \
        test/utils/dialogs/sync_options_dialog_test.dart
git commit -m "feat: add latestDate to SyncOptions and replace date ListTile with From→To chip row

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Open the PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/sync-date-range-ui
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create \
  --title "feat: add date range picker to SyncOptionsDialog" \
  --body "$(cat <<'EOF'
## Summary
- Adds `latestDate: DateTime?` to `SyncOptions` model
- Replaces the single earliest-date `ListTile` in `SyncOptionsDialog` with an inline **From → To** chip row
- To chip is disabled (greyed, `IgnorePointer`) until a From date is set
- Clearing From also clears To
- Checking "Fetch last 50" hides the entire chip row and clears both dates
- No changes to callers or API wiring — that is Task 4

## Test plan
- [ ] Run `flutter test test/utils/dialogs/sync_options_dialog_test.dart` — all 9 tests pass
- [ ] Open the app, tap the sync button on any list screen — From → To chips visible
- [ ] Set a From date — To chip becomes tappable
- [ ] Set a To date — both chips show date values with ✕ clear buttons
- [ ] Clear From — To also clears
- [ ] Check "Fetch last 50" — chip row disappears

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
