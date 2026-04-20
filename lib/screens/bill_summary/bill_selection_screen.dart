import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/bill.dart';
import '../../data/models/rentor.dart';
import '../../services/bill_summary/bill_summary_service.dart';
import 'message_preview_screen.dart';

/// Step 1 of the bill summary wizard.
///
/// Shows a checkbox list of [eligibleBills] for [rentor]. All bills are
/// pre-checked. Tapping "Generate Message" calls [BillSummaryService] and
/// pushes [MessagePreviewScreen].
class BillSelectionScreen extends StatefulWidget {
  final Rentor rentor;
  final List<Bill> eligibleBills;

  const BillSelectionScreen({
    super.key,
    required this.rentor,
    required this.eligibleBills,
  });

  @override
  State<BillSelectionScreen> createState() => _BillSelectionScreenState();
}

class _BillSelectionScreenState extends State<BillSelectionScreen> {
  late Set<String> _selectedIds;

  final _dateFormat = DateFormat('MMM d');

  @override
  void initState() {
    super.initState();
    // Pre-select all eligible bills.
    _selectedIds = widget.eligibleBills.map((b) => b.billId).toSet();
  }

  void _toggleBill(String billId, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedIds.add(billId);
      } else {
        _selectedIds.remove(billId);
      }
    });
  }

  void _generateMessage() {
    final selectedBills = widget.eligibleBills
        .where((b) => _selectedIds.contains(b.billId))
        .toList();
    final message = BillSummaryService()
        .generateMessage(widget.rentor, selectedBills);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagePreviewScreen(initialMessage: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Bills')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.eligibleBills.length,
              itemBuilder: (context, index) {
                final bill = widget.eligibleBills[index];
                final isSelected = _selectedIds.contains(bill.billId);
                final owedAmount =
                    Rentor.calculateOwedAmount(widget.rentor, bill);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) => _toggleBill(bill.billId, value),
                  title: Text('${bill.type.name} — ${bill.companyName}'),
                  subtitle: Text(
                    'Due: ${_dateFormat.format(bill.dueDate)} · '
                    'Total: \$${bill.amount.toStringAsFixed(2)} · '
                    'Your share: \$${owedAmount.toStringAsFixed(2)}',
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton(
              onPressed: _selectedIds.isEmpty ? null : _generateMessage,
              child: const Text('Generate Message'),
            ),
          ),
        ],
      ),
    );
  }
}
