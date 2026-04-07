import 'package:flutter/material.dart';

import '../../data/models/bill.dart';
import '../../data/models/email_data.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/email_data_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../bills/add_edit_bill_screen.dart';
import '../payments/add_edit_payment_screen.dart';

/// Screen for reviewing and editing an [EmailData] record.
///
/// Displays the raw email subject and (optionally) the full body, lets the
/// user link or re-link the email to a [Bill] or [Payment] from dropdowns,
/// and allows toggling the `processed` flag.  Changes are persisted via
/// [EmailDataRepository].
class EditEmailDataScreen extends StatefulWidget {
  /// The email record to display and optionally edit.
  final EmailData emailData;

  const EditEmailDataScreen({super.key, required this.emailData});

  @override
  State<EditEmailDataScreen> createState() => _EditEmailDataScreenState();
}

class _EditEmailDataScreenState extends State<EditEmailDataScreen> {
  final EmailDataRepository _emailDataRepository = EmailDataRepository();
  final BillsRepository _billsRepository = BillsRepository();
  final PaymentsRepository _paymentsRepository = PaymentsRepository();

  late bool _processed;
  String? _selectedBillId;
  String? _selectedPaymentId;
  bool _isBodyExpanded = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _processed = widget.emailData.processed;
    _selectedBillId = widget.emailData.billId;
    _selectedPaymentId = widget.emailData.paymentId;
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _billsRepository.reload(),
      _paymentsRepository.reload(),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final updated = EmailData(
      id: widget.emailData.id,
      emailDataId: widget.emailData.emailDataId,
      emailSubject: widget.emailData.emailSubject,
      emailBody: widget.emailData.emailBody,
      emailId: widget.emailData.emailId,
      billId: _selectedBillId,
      paymentId: _selectedPaymentId,
      processed: _processed,
    );

    final result = await _emailDataRepository.update(updated);
    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Failed to save email data.'),
        ),
      );
    }
  }

  Bill? get _selectedBill {
    if (_selectedBillId == null) return null;
    final matches = _billsRepository.bills.where((b) => b.billId == _selectedBillId);
    return matches.isNotEmpty ? matches.first : null;
  }

  Payment? get _selectedPayment {
    if (_selectedPaymentId == null) return null;
    final matches = _paymentsRepository.payments.where((p) => p.paymentId == _selectedPaymentId);
    return matches.isNotEmpty ? matches.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Email')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Subject (read-only)
                          TextFormField(
                            initialValue: widget.emailData.emailSubject,
                            decoration:
                                const InputDecoration(labelText: 'Subject'),
                            readOnly: true,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),

                          // Email body (collapsible)
                          InkWell(
                            onTap: () => setState(
                                () => _isBodyExpanded = !_isBodyExpanded),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Email Body',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                  Icon(
                                    _isBodyExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.grey.shade300),
                            ),
                            child: _isBodyExpanded
                                ? SelectableText(
                                    widget.emailData.emailBody,
                                    style: const TextStyle(fontSize: 13),
                                  )
                                : Text(
                                    widget.emailData.emailBody.length > 200
                                        ? '${widget.emailData.emailBody.substring(0, 200)}...'
                                        : widget.emailData.emailBody,
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.grey),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                          const SizedBox(height: 16),

                          // Processed toggle
                          SwitchListTile(
                            title: const Text('Processed'),
                            subtitle: const Text(
                                'Mark this email as processed'),
                            value: _processed,
                            onChanged: (value) =>
                                setState(() => _processed = value),
                            contentPadding: EdgeInsets.zero,
                          ),
                          const Divider(),
                          const SizedBox(height: 8),

                          // Linked Bill dropdown + edit button
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  initialValue: _billsRepository.bills.any(
                                          (b) => b.billId == _selectedBillId)
                                      ? _selectedBillId
                                      : null,
                                  decoration: const InputDecoration(
                                      labelText: 'Linked Bill'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('None'),
                                    ),
                                    ..._billsRepository.bills.map((Bill bill) {
                                      return DropdownMenuItem<String?>(
                                        value: bill.billId,
                                        child: Text(
                                          '${bill.companyName} – ${bill.dueDate} (\$${bill.amount.toStringAsFixed(2)})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: (value) => setState(
                                      () => _selectedBillId = value),
                                ),
                              ),
                              if (_selectedBill != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Edit linked bill',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            AddEditBillScreen(
                                                bill: _selectedBill),
                                      ),
                                    );
                                    await _billsRepository.reload();
                                    setState(() {});
                                  },
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Linked Payment dropdown + edit button
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  initialValue: _paymentsRepository.payments.any(
                                          (p) =>
                                              p.paymentId ==
                                              _selectedPaymentId)
                                      ? _selectedPaymentId
                                      : null,
                                  decoration: const InputDecoration(
                                      labelText: 'Linked Payment'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('None'),
                                    ),
                                    ..._paymentsRepository.payments
                                        .map((Payment payment) {
                                      return DropdownMenuItem<String?>(
                                        value: payment.paymentId,
                                        child: Text(
                                          '${payment.paymentDate} – \$${payment.amountPaid.toStringAsFixed(2)} (${payment.rentorName})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: (value) => setState(
                                      () => _selectedPaymentId = value),
                                ),
                              ),
                              if (_selectedPayment != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Edit linked payment',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            AddEditPaymentScreen(
                                                payment: _selectedPayment),
                                      ),
                                    );
                                    await _paymentsRepository.reload();
                                    setState(() {});
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
