import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/helpers/bills/bills_helper.dart';
import 'package:utility_bills_manager/helpers/rentors/rentors_helper.dart';

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
  final _percentageController = TextEditingController();
  final _amountPaidController = TextEditingController();
  final _lastPaymentDateController = TextEditingController();
  final Map<BillType, TextEditingController> _billPercentageControllers = {};

  final RentorsHelper _rentorsHelper = RentorsHelper();
  final BillsHelper _billsHelper = BillsHelper();

  DateTime? _lastPaymentDate;

  @override
  void initState() {
    super.initState();
    if (widget.rentor != null) {
      final rentor = widget.rentor!;
      _nameController.text = rentor.name;
      _percentageController.text = rentor.defaultPercentage.toStringAsFixed(2);
      _amountPaidController.text = rentor.amountPaid!.toStringAsFixed(2);
      if (rentor.lastPaymentDate != null) {
        _lastPaymentDateController.text = rentor.lastPaymentDate!;
        _lastPaymentDate = DateFormat('yyyy-MM-dd').parse(rentor.lastPaymentDate!);
      }

      // Populate existing bill-specific percentages
      for (var type in BillType.values) {
        _billPercentageControllers[type] = TextEditingController(
          text: rentor.billPercentages[type]?.toStringAsFixed(2) ?? '',
        );
      }
    } else {
      // Init empty controllers
      for (var type in BillType.values) {
        _billPercentageControllers[type] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _percentageController.dispose();
    _amountPaidController.dispose();
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
  final unpaidBills = allBills.where((bill) => bill.status != PaymentStatus.paid);

  double totalOwed = 0.0;

  for (var bill in unpaidBills) {
    final percent = widget.rentor!.billPercentages[bill.type] ?? widget.rentor!.defaultPercentage;
    totalOwed += bill.amount * (percent / 100);
  }

  return totalOwed;
}

  Widget _buildBillTypeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text('Bill-Specific Percentages', style: TextStyle(fontWeight: FontWeight.bold)),
        ...BillType.values.map((type) {
          return TextFormField(
            controller: _billPercentageControllers[type],
            decoration: InputDecoration(
              labelText: '${type.name[0].toUpperCase()}${type.name.substring(1)} %',
              hintText: 'Leave empty to use default',
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) return null;
              final percent = double.tryParse(value);
              if (percent == null || percent < 0 || percent > 100) {
                return 'Enter a valid percentage';
              }
              return null;
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
      name: _nameController.text,
      defaultPercentage: double.parse(_percentageController.text),
      amountPaid: double.tryParse(_amountPaidController.text) ?? 0.0,
      lastPaymentDate: _lastPaymentDate != null ? DateFormat('yyyy-MM-dd').format(_lastPaymentDate!) : null,
      billPercentages: billPercentages,
    );

    if (widget.rentor == null) {
      await _rentorsHelper.createRentor(rentor);
    } else {
      await _rentorsHelper.updateRentor(rentor);
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
        title: Text(isEditing ? 'Add Rentor' : 'Edit Rentor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator:
                    (value) => value!.isEmpty ? 'Enter name name' : null,
              ),
              TextFormField(
                controller: _percentageController,
                decoration: const InputDecoration(labelText: 'Percentage %'),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? 'Enter percentage' : null,
              ),
              _buildBillTypeFields(),
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
              TextFormField(
                controller: _amountPaidController,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Amount Paid \$'),
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
