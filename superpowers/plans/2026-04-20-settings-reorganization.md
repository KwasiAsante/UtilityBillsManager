# Settings Screen Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the "Sync Settings" card in `ServerConfigScreen` into two clearly named sections ("Manual Sync" and "Background Sync") and add always-visible helper text under each sync field.

**Architecture:** All changes are confined to `lib/screens/settings/server_config_screen.dart`. The data model, save logic, and validation are untouched — only section labels and `InputDecoration.helperText` are modified.

**Tech Stack:** Flutter widget tests (`flutter_test`), `shared_preferences` mock

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/screens/settings/server_config_screen.dart` | Modify | Reorganize sync sections, add helper text |
| `test/screens/settings/server_config_screen_test.dart` | Create | Widget tests for section labels and helper text |

---

### Task 1: Create the feature branch

- [ ] **Step 1: Create and check out the branch**

```bash
git checkout -b feat/settings-reorganization
```

- [ ] **Step 2: Verify**

```bash
git branch --show-current
```
Expected: `feat/settings-reorganization`

---

### Task 2: Write failing widget tests

- [ ] **Step 1: Create the test directory**

```bash
mkdir -p test/screens/settings
```

- [ ] **Step 2: Create `test/screens/settings/server_config_screen_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:utility_bills_manager/screens/settings/server_config_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen() {
    return const MaterialApp(home: ServerConfigScreen());
  }

  group('ServerConfigScreen section labels', () {
    testWidgets('shows Manual Sync section label', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Manual Sync'), findsOneWidget);
    });

    testWidgets('shows Background Sync section label', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Background Sync'), findsOneWidget);
    });

    testWidgets('does not show old Sync Settings label', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Sync Settings'), findsNothing);
    });
  });

  group('ServerConfigScreen helper text', () {
    testWidgets('shows helper text for Default Earliest Email Date', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The default start date used when you trigger a manual sync. '
          'You can override this each time in the sync dialog.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows helper text for Sync Delay', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'How long to wait after the app starts before the first background sync runs.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows helper text for Sync Interval', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'How often the app checks for new emails in the background. '
          '900 = every 15 minutes.',
        ),
        findsOneWidget,
      );
    });
  });
}
```

- [ ] **Step 3: Run the tests to confirm they fail**

```bash
flutter test test/screens/settings/server_config_screen_test.dart
```

Expected: 6 tests FAIL — `Manual Sync` and `Background Sync` labels don't exist, `Sync Settings` is still present, and helper texts are absent.

---

### Task 3: Implement the changes in `server_config_screen.dart`

- [ ] **Step 1: Read the current file**

Read `lib/screens/settings/server_config_screen.dart` in full before editing.

- [ ] **Step 2: Rename the "Sync Settings" section label to "Manual Sync" and scope it to the date field only**

Find this block (currently the entire Sync Settings section):

```dart
                // ── Sync settings ──────────────────────────────────────────────
                Text(
                  'Sync Settings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _earliestDateController,
                          decoration: InputDecoration(
                            labelText: 'Earliest Email Date',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today_outlined),
                              onPressed: _pickDate,
                            ),
                          ),
                          readOnly: true,
                          onTap: _pickDate,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _syncDelayController,
                          decoration: const InputDecoration(
                            labelText: 'Sync Delay (seconds)',
                            hintText: '30',
                          ),
                          keyboardType: TextInputType.number,
                          validator:
                              (v) => _validateInt(
                                v,
                                'Sync Delay',
                                allowZero: true,
                              ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _syncIntervalController,
                          decoration: const InputDecoration(
                            labelText: 'Sync Interval (seconds)',
                            hintText: '900',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) => _validateInt(v, 'Sync Interval'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
```

Replace it with:

```dart
                // ── Manual Sync ────────────────────────────────────────────────
                Text(
                  'Manual Sync',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _earliestDateController,
                      decoration: InputDecoration(
                        labelText: 'Default Earliest Email Date',
                        helperText:
                            'The default start date used when you trigger a manual sync. '
                            'You can override this each time in the sync dialog.',
                        helperMaxLines: 3,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today_outlined),
                          onPressed: _pickDate,
                        ),
                      ),
                      readOnly: true,
                      onTap: _pickDate,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Background Sync ────────────────────────────────────────────
                Text(
                  'Background Sync',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _syncDelayController,
                          decoration: const InputDecoration(
                            labelText: 'Sync Delay (seconds)',
                            hintText: '30',
                            helperText:
                                'How long to wait after the app starts before the first background sync runs.',
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          validator:
                              (v) => _validateInt(
                                v,
                                'Sync Delay',
                                allowZero: true,
                              ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _syncIntervalController,
                          decoration: const InputDecoration(
                            labelText: 'Sync Interval (seconds)',
                            hintText: '900',
                            helperText:
                                'How often the app checks for new emails in the background. '
                                '900 = every 15 minutes.',
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) => _validateInt(v, 'Sync Interval'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
```

- [ ] **Step 3: Verify the file compiles**

```bash
flutter analyze lib/screens/settings/server_config_screen.dart
```
Expected: no errors or warnings.

---

### Task 4: Run tests and commit

- [ ] **Step 1: Run the settings screen tests**

```bash
flutter test test/screens/settings/server_config_screen_test.dart
```
Expected: All 6 tests PASS.

- [ ] **Step 2: Run the full test suite**

```bash
flutter test
```
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings/server_config_screen.dart \
        test/screens/settings/server_config_screen_test.dart
git commit -m "feat: reorganize ServerConfigScreen sync settings into Manual Sync and Background Sync sections

Adds helper text to each sync field explaining its purpose.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Open the PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/settings-reorganization
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create \
  --title "feat: reorganize sync settings into Manual Sync and Background Sync sections" \
  --body "$(cat <<'EOF'
## Summary
- Splits the "Sync Settings" card in ServerConfigScreen into two clearly named sections: **Manual Sync** (earliest date) and **Background Sync** (delay + interval)
- Renames "Earliest Email Date" → "Default Earliest Email Date" for clarity
- Adds always-visible `helperText` below each sync field explaining its purpose
- No changes to data model, save logic, or validation

## Test plan
- [ ] Run `flutter test test/screens/settings/server_config_screen_test.dart` — all 6 tests pass
- [ ] Open the app, navigate to Settings → Server Configuration — "Manual Sync" and "Background Sync" sections visible
- [ ] Helper text visible below Default Earliest Email Date, Sync Delay, and Sync Interval fields
- [ ] Save still works correctly

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
