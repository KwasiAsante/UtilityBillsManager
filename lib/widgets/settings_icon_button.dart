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
