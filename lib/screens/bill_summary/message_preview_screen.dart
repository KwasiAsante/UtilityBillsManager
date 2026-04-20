import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Step 2 of the bill summary wizard.
///
/// Shows [initialMessage] in an editable [TextField]. Tapping "Share" opens
/// the system share sheet via [share_plus]. If sharing is unavailable on the
/// current platform, the message is copied to the clipboard instead.
class MessagePreviewScreen extends StatefulWidget {
  final String initialMessage;

  const MessagePreviewScreen({super.key, required this.initialMessage});

  @override
  State<MessagePreviewScreen> createState() => _MessagePreviewScreenState();
}

class _MessagePreviewScreenState extends State<MessagePreviewScreen> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final text = _controller.text;
    final result =
        await SharePlus.instance.share(ShareParams(text: text));
    if (result.status == ShareResultStatus.unavailable && mounted) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message copied to clipboard')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bill Summary Message')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Edit your message here…',
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }
}
