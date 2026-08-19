import 'package:flutter/material.dart';

import '../../widgets/responsive_constraint.dart';
import 'app_config_screen.dart';
import 'log_viewer_screen.dart';
import 'server_config_screen.dart';

/// Landing screen for app settings.
///
/// Presents navigation tiles for [AppConfigScreen], [ServerConfigScreen], and
/// [LogViewerScreen] — so each configuration domain is edited independently.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ResponsiveConstraint(
        maxWidth: 560,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.api_outlined),
              title: const Text('App Configuration'),
              subtitle: const Text('API base URL'),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => Navigator.push(
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
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ServerConfigScreen(),
                    ),
                  ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Logs'),
              subtitle: const Text('View and share on-device log files'),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LogViewerScreen()),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
