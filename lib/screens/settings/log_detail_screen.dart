import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/logs/log_file_service.dart';

/// Shows the contents of a single on-device log file, with an option to
/// share it via the system share sheet.
class LogDetailScreen extends StatefulWidget {
  final File file;

  const LogDetailScreen({super.key, required this.file});

  @override
  State<LogDetailScreen> createState() => _LogDetailScreenState();
}

class _LogDetailScreenState extends State<LogDetailScreen> {
  late final Future<List<String>> _linesFuture = widget.file.readAsLines();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.uri.pathSegments.last),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share log file',
            onPressed: () => LogFileService.shareFile(widget.file),
          ),
        ],
      ),
      body: FutureBuilder<List<String>>(
        future: _linesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Failed to read log file: ${snapshot.error}'),
            );
          }
          final lines = snapshot.data!;
          if (lines.isEmpty) {
            return const Center(child: Text('This log file is empty.'));
          }
          return SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: lines.length,
              itemBuilder:
                  (context, index) => Text(
                    lines[index],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
            ),
          );
        },
      ),
    );
  }
}
