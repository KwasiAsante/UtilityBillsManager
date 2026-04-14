# Settings UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a settings UI with a gear icon in each tab screen's AppBar that opens a landing screen navigating to two independent sub-screens: App Configuration and Server Configuration.

**Architecture:** A reusable `SettingsIconButton` widget is added to all 5 existing tab screens' AppBar actions. It pushes a `SettingsScreen` landing page with two `ListTile` rows that each navigate to their own `StatefulWidget` form screen with independent save logic.

**Tech Stack:** Flutter, Material 3, `AppConfig` / `ServerConfiguration` static classes, `SharedPreferences` (via existing `Preferences` util), no new packages.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/widgets/settings_icon_button.dart` | **Create** | Reusable AppBar action that pushes SettingsScreen |
| `lib/screens/settings/settings_screen.dart` | **Create** | Landing screen with two navigation tiles |
| `lib/screens/settings/app_config_screen.dart` | **Create** | App Configuration form (API base URL) |
| `lib/screens/settings/server_config_screen.dart` | **Create** | Server Configuration form (email + IMAP + sync) |
| `lib/screens/bills/bill_list_screen.dart` | **Modify** | Add SettingsIconButton to AppBar actions |
| `lib/screens/rentors/rentor_list_screen.dart` | **Modify** | Add SettingsIconButton to AppBar actions |
| `lib/screens/summary/summary_screen.dart` | **Modify** | Add SettingsIconButton to AppBar actions |
| `lib/screens/payments/payment_list_screen.dart` | **Modify** | Add SettingsIconButton to AppBar actions |
| `lib/screens/emails/email_list_screen.dart` | **Modify** | Add SettingsIconButton to AppBar actions |

---

## Task 1: SettingsIconButton widget

**Files:**
- Create: `lib/widgets/settings_icon_button.dart`

- [ ] **Step 1: Create the widget**

Create `lib/widgets/settings_icon_button.dart`:

```dart
import 'package:flutter/material.dart';

import '../screens/settings/settings_screen.dart';

/// An [AppBar] action that opens [SettingsScreen].
///
/// Drop it into any screen's `AppBar.actions`:
/// ```dart
/// appBar: AppBar(
///   actions: [
///     const SettingsIconButton(),
///   ],
/// )
/// ```
class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Create empty SettingsScreen so the import resolves**

Create `lib/screens/settings/settings_screen.dart` with a minimal stub (will be replaced in Task 2):

```dart
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SizedBox.shrink(),
    );
  }
}
```

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/widgets/settings_icon_button.dart lib/screens/settings/settings_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/settings_icon_button.dart lib/screens/settings/settings_screen.dart
git commit -m "feat: add SettingsIconButton widget and stub SettingsScreen"
```

---

## Task 2: SettingsScreen landing page

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Replace stub with landing screen**

Replace the full contents of `lib/screens/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_config_screen.dart';
import 'server_config_screen.dart';

/// Landing screen for app settings.
///
/// Presents two navigation tiles — one for [AppConfigScreen] and one for
/// [ServerConfigScreen] — so each configuration domain is edited independently.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.api_outlined),
            title: const Text('App Configuration'),
            subtitle: const Text('API base URL'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppConfigScreen()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Server Configuration'),
            subtitle: const Text('Email, IMAP and sync settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServerConfigScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create empty stubs for the two sub-screens so imports resolve**

Create `lib/screens/settings/app_config_screen.dart`:

```dart
import 'package:flutter/material.dart';

class AppConfigScreen extends StatefulWidget {
  const AppConfigScreen({super.key});

  @override
  State<AppConfigScreen> createState() => _AppConfigScreenState();
}

class _AppConfigScreenState extends State<AppConfigScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Configuration')),
      body: const SizedBox.shrink(),
    );
  }
}
```

Create `lib/screens/settings/server_config_screen.dart`:

```dart
import 'package:flutter/material.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Configuration')),
      body: const SizedBox.shrink(),
    );
  }
}
```

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/screens/settings/
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings/settings_screen.dart lib/screens/settings/app_config_screen.dart lib/screens/settings/server_config_screen.dart
git commit -m "feat: add SettingsScreen landing page and sub-screen stubs"
```

---

## Task 3: Add SettingsIconButton to all 5 tab screens

**Files:**
- Modify: `lib/screens/bills/bill_list_screen.dart`
- Modify: `lib/screens/rentors/rentor_list_screen.dart`
- Modify: `lib/screens/summary/summary_screen.dart`
- Modify: `lib/screens/payments/payment_list_screen.dart`
- Modify: `lib/screens/emails/email_list_screen.dart`

Each screen already has an `AppBar` with `actions: [const NotificationBellIcon(), ...]`. Add the import and insert `const SettingsIconButton()` as the **last** item in each `actions` list.

- [ ] **Step 1: Update bill_list_screen.dart**

Add import at the top of `lib/screens/bills/bill_list_screen.dart`:
```dart
import '../../widgets/settings_icon_button.dart';
```

Find the `actions:` list inside `AppBar(` and append `const SettingsIconButton()`:
```dart
actions: [
  const NotificationBellIcon(),
  // ... existing actions ...
  const SettingsIconButton(),
],
```

- [ ] **Step 2: Update rentor_list_screen.dart**

Add import at the top of `lib/screens/rentors/rentor_list_screen.dart`:
```dart
import '../../widgets/settings_icon_button.dart';
```

Find the `actions:` list (around line 168) and append:
```dart
actions: [
  const NotificationBellIcon(),
  // ... existing actions ...
  const SettingsIconButton(),
],
```

- [ ] **Step 3: Update summary_screen.dart**

Add import at the top of `lib/screens/summary/summary_screen.dart`:
```dart
import '../../widgets/settings_icon_button.dart';
```

Find the `actions:` list inside `AppBar(` and append:
```dart
actions: [
  const NotificationBellIcon(),
  // ... existing actions ...
  const SettingsIconButton(),
],
```

- [ ] **Step 4: Update payment_list_screen.dart**

Add import at the top of `lib/screens/payments/payment_list_screen.dart`:
```dart
import '../../widgets/settings_icon_button.dart';
```

Find the `actions:` list (around line 349) and append:
```dart
actions: [
  const NotificationBellIcon(),
  // ... existing actions ...
  const SettingsIconButton(),
],
```

- [ ] **Step 5: Update email_list_screen.dart**

Add import at the top of `lib/screens/emails/email_list_screen.dart`:
```dart
import '../../widgets/settings_icon_button.dart';
```

Find the `actions:` list inside `AppBar(` and append:
```dart
actions: [
  const NotificationBellIcon(),
  // ... existing actions ...
  const SettingsIconButton(),
],
```

- [ ] **Step 6: Verify it compiles**

```bash
flutter analyze lib/screens/
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/bills/bill_list_screen.dart lib/screens/rentors/rentor_list_screen.dart lib/screens/summary/summary_screen.dart lib/screens/payments/payment_list_screen.dart lib/screens/emails/email_list_screen.dart
git commit -m "feat: add SettingsIconButton to all tab screen AppBars"
```

---

## Task 4: AppConfigScreen form

**Files:**
- Modify: `lib/screens/settings/app_config_screen.dart`

- [ ] **Step 1: Replace stub with full form**

Replace the full contents of `lib/screens/settings/app_config_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../config/app_config.dart';

/// Settings form for [AppConfig] — currently exposes only the API base URL.
class AppConfigScreen extends StatefulWidget {
  const AppConfigScreen({super.key});

  @override
  State<AppConfigScreen> createState() => _AppConfigScreenState();
}

class _AppConfigScreenState extends State<AppConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _apiUrlController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: AppConfig.apiBaseUrl);
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AppConfig.setApiBaseUrl(_apiUrlController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App configuration saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Configuration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'General',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextFormField(
                    controller: _apiUrlController,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      hintText: 'http://127.0.0.1:8080',
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _saveSettings,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/screens/settings/app_config_screen.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings/app_config_screen.dart
git commit -m "feat: implement AppConfigScreen form"
```

---

## Task 5: ServerConfigScreen form

**Files:**
- Modify: `lib/screens/settings/server_config_screen.dart`

- [ ] **Step 1: Replace stub with full form**

Replace the full contents of `lib/screens/settings/server_config_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/server_configuration.dart';

/// Settings form for [ServerConfiguration] — email credentials, IMAP settings,
/// and sync scheduling.
class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _emailAddressController;
  late final TextEditingController _emailPasswordController;
  late final TextEditingController _imapServerController;
  late final TextEditingController _imapPortController;
  late final TextEditingController _earliestDateController;
  late final TextEditingController _syncDelayController;
  late final TextEditingController _syncIntervalController;

  bool _imapSecure = true;
  bool _passwordVisible = false;
  bool _saving = false;

  DateTime? _earliestDate;
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _emailAddressController = TextEditingController(
      text: ServerConfiguration.emailAddress,
    );
    _emailPasswordController = TextEditingController(
      text: ServerConfiguration.emailPassword,
    );
    _imapServerController = TextEditingController(
      text: ServerConfiguration.emailImapServer,
    );
    _imapPortController = TextEditingController(
      text: ServerConfiguration.emailImapPort.toString(),
    );
    _imapSecure = ServerConfiguration.emailImapSecure;
    _earliestDate = ServerConfiguration.emailEarliestDate;
    _earliestDateController = TextEditingController(
      text: _dateFormat.format(_earliestDate!),
    );
    _syncDelayController = TextEditingController(
      text: ServerConfiguration.emailSyncDelayDuration.inSeconds.toString(),
    );
    _syncIntervalController = TextEditingController(
      text: ServerConfiguration.emailSyncInterval.inSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _emailAddressController.dispose();
    _emailPasswordController.dispose();
    _imapServerController.dispose();
    _imapPortController.dispose();
    _earliestDateController.dispose();
    _syncDelayController.dispose();
    _syncIntervalController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _earliestDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _earliestDate = picked;
        _earliestDateController.text = _dateFormat.format(picked);
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ServerConfiguration.setEmailAddress(
        _emailAddressController.text.trim(),
      );
      await ServerConfiguration.setEmailPassword(
        _emailPasswordController.text,
      );
      await ServerConfiguration.setEmailImapServer(
        _imapServerController.text.trim(),
      );
      await ServerConfiguration.setEmailImapPort(
        int.parse(_imapPortController.text.trim()),
      );
      await ServerConfiguration.setEmailImapSecure(_imapSecure);
      if (_earliestDate != null) {
        await ServerConfiguration.setEmailEarliestDate(_earliestDate!);
      }
      await ServerConfiguration.setEmailSyncDelayDuration(
        Duration(seconds: int.parse(_syncDelayController.text.trim())),
      );
      await ServerConfiguration.setEmailSyncInterval(
        Duration(seconds: int.parse(_syncIntervalController.text.trim())),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server configuration saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateInt(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (int.tryParse(value.trim()) == null) {
      return '$fieldName must be a whole number';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Configuration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Email credentials ──────────────────────────────────────────
              Text(
                'Email Account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Email Password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                          ),
                        ),
                        obscureText: !_passwordVisible,
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── IMAP settings ──────────────────────────────────────────────
              Text(
                'IMAP Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _imapServerController,
                        decoration: const InputDecoration(
                          labelText: 'IMAP Server',
                          hintText: 'imap.gmail.com',
                        ),
                        autocorrect: false,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _imapPortController,
                        decoration: const InputDecoration(
                          labelText: 'IMAP Port',
                          hintText: '993',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) => _validateInt(v, 'IMAP Port'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use Secure Connection (TLS)'),
                        value: _imapSecure,
                        onChanged: (v) => setState(() => _imapSecure = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

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
                        validator: (v) => _validateInt(v, 'Sync Delay'),
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

              FilledButton(
                onPressed: _saving ? null : _saveSettings,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/screens/settings/server_config_screen.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings/server_config_screen.dart
git commit -m "feat: implement ServerConfigScreen form"
```

---

## Task 6: Manual smoke test

- [ ] **Step 1: Run the app**

```bash
flutter run
```

- [ ] **Step 2: Verify settings icon appears**

Open any tab. Confirm the gear icon (`settings_outlined`) appears in the top-right of the AppBar alongside the notification bell.

- [ ] **Step 3: Verify navigation**

Tap the gear icon → `Settings` landing screen appears with two tiles: "App Configuration" and "Server Configuration".

Tap "App Configuration" → `AppConfigScreen` shows with API Base URL prefilled from `AppConfig.apiBaseUrl`.

Tap back → tap "Server Configuration" → `ServerConfigScreen` shows with all fields prefilled from `ServerConfiguration.*`.

- [ ] **Step 4: Verify save**

On `AppConfigScreen`: change the API URL, tap Save → `SnackBar('App configuration saved')` appears. Hot-restart the app and re-open `AppConfigScreen` to confirm the new value persisted.

On `ServerConfigScreen`: change the email address, tap Save → `SnackBar('Server configuration saved')` appears. Hot-restart and confirm.

- [ ] **Step 5: Verify validation**

On `ServerConfigScreen`: set IMAP Port to "abc", tap Save → inline error "IMAP Port must be a whole number" appears, save is blocked.

- [ ] **Step 6: Final commit (if any fixups were needed)**

```bash
git add -p
git commit -m "fix: settings UI smoke test fixups"
```
