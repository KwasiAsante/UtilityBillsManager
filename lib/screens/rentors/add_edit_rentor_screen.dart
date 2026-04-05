import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/data/repositories/rentors_repository.dart';
import 'package:utility_bills_manager/helpers/bills/bills_helper.dart';

class AddEditRentorScreen extends StatefulWidget {
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
  final BillsHelper _billsHelper = BillsHelper();

  DateTime? _lastPaymentDate;
  late List<BillType> _selectedBillTypes;
  late List<BillType> _excludedBillTypes;

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
        _lastPaymentDateController.text = rentor.lastPaymentDate!;
        _lastPaymentDate = DateFormat('yyyy-MM-dd').parse(rentor.lastPaymentDate!);
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

  Future<double> _calculateAmountOwed() async {
  if (widget.rentor == null) return 0.0;

  final result = await _billsHelper.readAllBills();
  if (!result.isSuccess) return 0.0;

  final allBills = result.data!;
  final unpaidBills = allBills.where((bill) =>
      bill.status != PaymentStatus.paid &&
      !widget.rentor!.excludedBillTypes.contains(bill.type));

  double totalOwed = 0.0;

  for (var bill in unpaidBills) {
    final percent = widget.rentor!.billPercentages[bill.type] ?? widget.rentor!.defaultPercentage;
    totalOwed += bill.amount * (percent / 100);
  }

  return totalOwed;
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
      lastPaymentDate: _lastPaymentDate != null ? DateFormat('yyyy-MM-dd').format(_lastPaymentDate!) : null,
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
                      const SizedBox(height: 20),
                      FutureBuilder<double>(
                        future: _calculateAmountOwed(),
                        builder: (context, snapshot) {
                          final amount = snapshot.data?.toStringAsFixed(2) ?? '...';
                          return TextFormField(
                            enabled: false,
                            decoration: InputDecoration(
                              labelText: 'Amount Owed \$',
                              hintText: amount,
                            ),
                          );
                        },
                      ),
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
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

