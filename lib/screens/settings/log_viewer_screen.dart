import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/logs/log_file_service.dart';
import '../../widgets/responsive_constraint.dart';
import 'log_detail_screen.dart';

/// Lists on-device log files and lets you view or share them — useful for
/// debugging on a device that isn't connected to a debugger, or when the
/// server log sink isn't reachable.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  static final _dateFormat = DateFormat('MMM d, yyyy • HH:mm');

  late Future<List<File>> _filesFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = LogFileService.listLogFiles();
  }

  void _refresh() {
    setState(() => _filesFuture = LogFileService.listLogFiles());
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Logs')),
        body: const Center(
          child: Text('Log files are not available on web.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          FutureBuilder<List<File>>(
            future: _filesFuture,
            builder: (context, snapshot) {
              final files = snapshot.data ?? const <File>[];
              return IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Share all logs',
                onPressed:
                    files.isEmpty
                        ? null
                        : () => LogFileService.shareAll(files),
              );
            },
          ),
        ],
      ),
      body: ResponsiveConstraint(
        child: FutureBuilder<List<File>>(
          future: _filesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final files = snapshot.data ?? const <File>[];
            if (files.isEmpty) {
              return const Center(child: Text('No log files yet.'));
            }
            return ListView.separated(
              itemCount: files.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final file = files[index];
                final stat = file.statSync();
                return ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(file.uri.pathSegments.last),
                  subtitle: Text(
                    '${_dateFormat.format(stat.modified)} • ${_formatSize(stat.size)}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Share',
                    onPressed: () => LogFileService.shareFile(file),
                  ),
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LogDetailScreen(file: file),
                        ),
                      ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
