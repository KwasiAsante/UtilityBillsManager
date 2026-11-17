import 'package:flutter/material.dart';

import '../utils/bills/bill_recalculation.dart';

/// A small warning icon shown next to a bill's status badge when the rentors
/// have paid but the Property Manager is still covering more than their share.
///
/// Hovering (or long-pressing) shows [BillGap.message] as a tooltip; tapping
/// opens a dialog with the same text.
class BillGapWarning extends StatelessWidget {
  const BillGapWarning({super.key, required this.gap});

  final BillGap gap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: gap.message,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Payment gap'),
            content: Text(gap.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Colors.orange.shade800,
            semanticLabel: 'Payment gap',
          ),
        ),
      ),
    );
  }
}
