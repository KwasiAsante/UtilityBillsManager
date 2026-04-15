import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../data/repositories/rentors_repository.dart';

/// Form screen for creating a new rentor or editing an existing one.
///
/// Pass a [rentor] to pre-populate the form fields; omit it to create a new
/// rentor.  On save the screen delegates to [RentorsRepository].  Supports
/// configuring a default split percentage, per-[BillType] overrides, and
/// bill types to exclude from the rentor's calculation.
class AddEditRentorScreen extends StatefulWidget {
  /// The rentor to edit, or `null` when creating a new one.
  final Rentor? rentor;

  const AddEditRentorScreen({super.key, this.rentor});

  @override
  State<StatefulWidget> createState() {
    return _AddEditRentorScreenState();
  }
}

class _AddEditRentorScreenState extends State<AddEditRentorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _percentageController = TextEditingController();
  final _lastPaymentDateController = TextEditingController();
  final Map<BillType, TextEditingController> _billPercentageControllers = {};

  final RentorsRepository _rentorsRepository = RentorsRepository();
  final BillsRepository _billsRepository = BillsRepository();
  final PaymentsRepository _paymentsRepository = PaymentsRepository();

  DateTime? _lastPaymentDate;
  late List<BillType> _selectedBillTypes;
  late List<BillType> _excludedBillTypes;
  final _amountOwedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.rentor != null) {
      final rentor = widget.rentor!;
      _nameController.text = rentor.name;
      _emailController.text = rentor.email ?? '';
      _phoneController.text = rentor.phone ?? '';
      _percentageController.text = rentor.defaultPercentage.toStringAsFixed(2);
      if (rentor.lastPaymentDate != null) {
        _lastPaymentDateController.text = DateFormat('yyyy-MM-dd').format(widget.rentor!.lastPaymentDate!);
        _lastPaymentDate = rentor.lastPaymentDate;
      }

      // Populate only existing bill-specific percentages
      _selectedBillTypes = rentor.billPercentages.keys.toList();
      for (var type in _selectedBillTypes) {
        _billPercentageControllers[type] = TextEditingController(
          text: rentor.billPercentages[type]!.toStringAsFixed(2),
        );
      }
      _excludedBillTypes = List<BillType>.from(rentor.excludedBillTypes);
    } else {
      _selectedBillTypes = [];
      _excludedBillTypes = [];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _percentageController.dispose();
    _lastPaymentDateController.dispose();
    _amountOwedController.dispose();
    for (var controller in _billPercentageControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastPaymentDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (picked != null) {
      setState(() {
        _lastPaymentDate = picked;
        _lastPaymentDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  double _getPercentageForBillType(BillType type) {
    final controller = _billPercentageControllers[type];
    if (controller != null && controller.text.trim().isNotEmpty) {
      return double.tryParse(controller.text.trim()) ?? 0.0;
    }
    return double.tryParse(_percentageController.text.trim()) ?? 0.0;
  }

  Future<void> _showCalculateAmountOwedDialog() async {
    if (_billsRepository.bills.isEmpty) {
      await _billsRepository.reload();
    }
    if (_paymentsRepository.payments.isEmpty) {
      await _paymentsRepository.reload();
    }

    final eligibleBills = _billsRepository.bills
        .where((b) => b.status == PaymentStatus.unpaid || b.status == PaymentStatus.partial)
        .toList();

    if (eligibleBills.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No unpaid or partial bills found')),
        );
      }
      return;
    }

    final Set<DateTime> periodSet = {};
    for (final bill in eligibleBills) {
      periodSet.add(DateTime(bill.dueDate.year, bill.dueDate.month));
    }
    final sortedPeriods = periodSet.toList()..sort((a, b) => a.compareTo(b));

    if (!mounted) return;

    final selectedPeriod = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MonthYearSelectionDialog(periods: sortedPeriods),
    );

    if (selectedPeriod == null || !mounted) return;

    final periodBills = eligibleBills
        .where((b) => b.dueDate.year == selectedPeriod.year && b.dueDate.month == selectedPeriod.month)
        .toList();

    // Sum payments already made by this rentor, keyed by billId.
    // For a new rentor (widget.rentor == null), rentorId is null so no payments
    // are subtracted — correct, since a new rentor has no payment history yet.
    final rentorId = widget.rentor?.rentorId;
    final Map<String, double> rentorPaidPerBill = {};
    if (rentorId != null) {
      for (final payment in _paymentsRepository.payments) {
        if (payment.rentorId == rentorId && payment.billIds != null) {
          for (final billId in payment.billIds!) {
            rentorPaidPerBill[billId] = (rentorPaidPerBill[billId] ?? 0.0) + payment.amountPaid;
          }
        }
      }
    }

    // A minimal Rentor is constructed to call calculateOwedBreakdown.
    // percentageForType is always supplied here (live form values), so
    // billPercentages and defaultPercentage on this object are never consulted
    // inside the extension method — only excludedBillTypes matters.
    // If percentageForType were ever omitted, defaultPercentage: 0.0 would
    // silently produce incorrect results.
    final tempRentor = Rentor(
      name: '',
      defaultPercentage: double.tryParse(_percentageController.text.trim()) ?? 0.0,
      billPercentages: const {},
      excludedBillTypes: _excludedBillTypes,
    );
    final breakdown = tempRentor.calculateOwedBreakdown(
      bills: periodBills,
      alreadyPaidPerBill: rentorPaidPerBill,
      percentageForType: _getPercentageForBillType,
    );

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AmountOwedResultDialog(
        period: selectedPeriod,
        breakdown: breakdown,
      ),
    );

    if (confirmed == true) {
      final total = breakdown.values.fold(0.0, (sum, v) => sum + v);
      final periodLabel = DateFormat('MMMM yyyy').format(selectedPeriod);
      setState(() {
        _amountOwedController.text = '$periodLabel – \$${total.toStringAsFixed(2)}';
      });
    }
  }

  void _showAddBillPercentageDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddBillPercentageDialog(
        selectedBillTypes: _selectedBillTypes,
        defaultPercentage: _percentageController.text,
        onAdd: (selectedType, percentage) {
          setState(() {
            _selectedBillTypes.add(selectedType);
            _billPercentageControllers[selectedType] = TextEditingController(
              text: percentage.toStringAsFixed(2),
            );
          });
        },
      ),
    );
  }

  void _removeBillPercentage(BillType type) {
    setState(() {
      _selectedBillTypes.remove(type);
      _billPercentageControllers[type]?.dispose();
      _billPercentageControllers.remove(type);
    });
  }

  Widget _buildBillTypeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Bill-Specific Percentages', style: TextStyle(fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: _selectedBillTypes.length < BillType.values.length
                  ? _showAddBillPercentageDialog
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_selectedBillTypes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'No bill percentages added yet',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: _selectedBillTypes.length,
            itemBuilder: (context, index) {
              final type = _selectedBillTypes[index];
              final controller = _billPercentageControllers[type]!;
              final displayName = '${type.name[0].toUpperCase()}${type.name.substring(1)}';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: '$displayName %',
                          hintText: 'Leave empty to use default',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          final percent = double.tryParse(value);
                          if (percent == null || percent < 0 || percent > 100) {
                            return 'Invalid %';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _removeBillPercentage(type),
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildExclusionListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text('Excluded Bill Types', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Payments for this rentor cannot be applied to bills of these types.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ...BillType.values.map((type) {
          final isExcluded = _excludedBillTypes.contains(type);
          return CheckboxListTile(
            dense: true,
            title: Text(type.name),
            value: isExcluded,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _excludedBillTypes.add(type);
                } else {
                  _excludedBillTypes.remove(type);
                }
              });
            },
          );
        }),
      ],
    );
  }

  Future<void> _saveRentor() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Build billPercentages map
    final billPercentages = <BillType, double>{};
    _billPercentageControllers.forEach((type, controller) {
      final val = controller.text.trim();
      if (val.isNotEmpty) {
        billPercentages[type] = double.parse(val);
      }
    });

    final rentor = Rentor(
      id: widget.rentor?.id,
      rentorId: widget.rentor?.rentorId,
      name: _nameController.text,
      email: _emailController.text.isNotEmpty ? _emailController.text : null,
      phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
      defaultPercentage: double.parse(_percentageController.text),
      lastPaymentDate: _lastPaymentDate,
      billPercentages: billPercentages,
      excludedBillTypes: _excludedBillTypes,
    );

    if (widget.rentor == null) {
      await _rentorsRepository.create(rentor);
    } else {
      await _rentorsRepository.update(rentor);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.rentor != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Rentor' : 'Add Rentor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator:
                            (value) => value!.isEmpty ? 'Enter name' : null,
                      ),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(labelText: 'Phone Number'),
                        keyboardType: TextInputType.phone,
                      ),
                      TextFormField(
                        controller: _percentageController,
                        decoration: const InputDecoration(labelText: 'Percentage %'),
                        keyboardType: TextInputType.number,
                        validator: (value) => value!.isEmpty ? 'Enter percentage' : null,
                      ),
                      _buildBillTypeFields(),
                      _buildExclusionListSection(),
                      GestureDetector(
                        onTap: _pickDate,
                        child: AbsorbPointer(
                          child: TextFormField(
                            controller: _lastPaymentDateController,
                            decoration: const InputDecoration(labelText: 'Last Payment Date'),
                            keyboardType: TextInputType.datetime,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _showCalculateAmountOwedDialog,
                            icon: const Icon(Icons.calculate),
                            label: const Text('Calculate Amount Owed'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _amountOwedController,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Amount Owed',
                                hintText: '—',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 25),
              FilledButton(
                onPressed: _saveRentor,
                child: const Text('Save Rentor'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthYearSelectionDialog extends StatefulWidget {
  final List<DateTime> periods;

  const _MonthYearSelectionDialog({required this.periods});

  @override
  State<_MonthYearSelectionDialog> createState() => _MonthYearSelectionDialogState();
}

class _MonthYearSelectionDialogState extends State<_MonthYearSelectionDialog> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.periods.first;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Period'),
      content: DropdownButton<DateTime>(
        value: _selected,
        isExpanded: true,
        items: widget.periods.map((period) {
          final label = DateFormat('MMMM yyyy').format(period);
          return DropdownMenuItem(value: period, child: Text(label));
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _selected = value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Next'),
        ),
      ],
    );
  }
}

class _AmountOwedResultDialog extends StatelessWidget {
  final DateTime period;
  final Map<BillType, double> breakdown;

  const _AmountOwedResultDialog({
    required this.period,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
    final total = breakdown.values.fold(0.0, (sum, v) => sum + v);
    final periodLabel = DateFormat('MMMM yyyy').format(period);

    return AlertDialog(
      title: Text('Amount Owed – $periodLabel'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (breakdown.isEmpty)
              const Text('No applicable bills for this period.')
            else
              ...breakdown.entries.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key.name),
                        Text('\$${entry.value.toStringAsFixed(2)}'),
                      ],
                    ),
                  )),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _AddBillPercentageDialog extends StatefulWidget {
  final List<BillType> selectedBillTypes;
  final String? defaultPercentage;
  final Function(BillType, double) onAdd;

  const _AddBillPercentageDialog({
    required this.selectedBillTypes,
    this.defaultPercentage,
    required this.onAdd,
  });

  @override
  State<_AddBillPercentageDialog> createState() => _AddBillPercentageDialogState();
}

class _AddBillPercentageDialogState extends State<_AddBillPercentageDialog> {
  BillType? selectedType;
  final percentageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    percentageController.text = widget.defaultPercentage ?? '';
  }

  @override
  void dispose() {
    percentageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Bill Percentage'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Bill Type:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            RadioGroup<BillType>(
              groupValue: selectedType,
              onChanged: (value) {
                setState(() {
                  selectedType = value;
                });
              },
              child: Column(
                children: BillType.values
                    .where((type) => !widget.selectedBillTypes.contains(type))
                    .map((type) => RadioListTile<BillType>(
                          title: Text('${type.name[0].toUpperCase()}${type.name.substring(1)}'),
                          value: type,
                        ))
                    .toList(),
              )
            ),
            const SizedBox(height: 20),
            TextField(
              controller: percentageController,
              decoration: const InputDecoration(
                labelText: 'Percentage %',
                hintText: 'Enter percentage (0-100)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (selectedType == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a bill type')),
              );
              return;
            }

            final percent = double.tryParse(percentageController.text.trim());
            if (percent == null || percent < 0 || percent > 100) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a valid percentage (0-100)')),
              );
              return;
            }

            widget.onAdd(selectedType!, percent);
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

