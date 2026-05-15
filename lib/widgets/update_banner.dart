import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update/update_info.dart';
import '../services/update/update_service.dart';
import '../utils/preferences.dart';

/// Wraps [child] and shows a [MaterialBanner] at the top of the screen when
/// a newer version of the app is available on GitHub Releases.
///
/// Dismissal is per-version: dismissing version X stores it in
/// [SharedPreferences] so the banner does not reappear on the same version.
/// When version Y is released, the banner shows again.
///
/// Place this widget as the direct parent of a [Scaffold]:
/// ```dart
/// return UpdateBanner(child: Scaffold(...));
/// ```
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  static const _dismissedKey = 'update_dismissed_for_version';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final info = await UpdateService.instance.checkForUpdate();
    if (info == null || !info.isUpdateAvailable) return;
    if (!mounted) return;

    final dismissed = Preferences.getString(_dismissedKey);
    if (dismissed == info.latestVersion) return;

    _showBanner(info);
  }

  void _showBanner(UpdateInfo info) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        leading: const Icon(Icons.system_update_alt, size: 28),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        content: Text(
          'Version ${info.latestVersion} is available  '
          '(you have ${info.currentVersion})',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              Preferences.setString(_dismissedKey, info.latestVersion);
            },
            child: const Text('Dismiss'),
          ),
          FilledButton.icon(
            onPressed: () => _onDownload(info),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  // ── Download handling ──────────────────────────────────────────────────────

  Future<void> _onDownload(UpdateInfo info) async {
    if (!kIsWeb && Platform.isWindows) {
      _showWindowsDownloadDialog(info);
    } else {
      final url = info.downloads.forPlatform;
      if (url != null) {
        await _launch(url);
      }
    }
  }

  /// On Windows we offer all three installer formats so the user can pick
  /// whichever matches how they originally installed the app.
  void _showWindowsDownloadDialog(UpdateInfo info) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update_alt, size: 36),
        title: Text('Update to ${info.latestVersion}'),
        content: const Text(
          'Choose your preferred installer format.\n\n'
          '• EXE — recommended for most users\n'
          '• MSI — for enterprise / IT deployment\n'
          '• MSIX — for the auto-update (appinstaller) flow',
        ),
        actions: [
          if (info.downloads.windowsExe != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _launch(info.downloads.windowsExe!);
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('EXE installer'),
            ),
          if (info.downloads.windowsMsi != null)
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _launch(info.downloads.windowsMsi!);
              },
              child: const Text('MSI installer'),
            ),
          if (info.downloads.windowsMsix != null)
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _launch(info.downloads.windowsMsix!);
              },
              child: const Text('MSIX package'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
