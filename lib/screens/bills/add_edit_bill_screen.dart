import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/repositories/bills_repository.dart';

class AddEditBillScreen extends StatefulWidget {
  final Bill? bill;

  const AddEditBillScreen({super.key, this.bill});

  @override
  State<StatefulWidget> createState() {
    return _AddEditBillScreenState();
  }
}

class _AddEditBillScreenState extends State<AddEditBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _amountController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _notesController = TextEditingController();
  final _amountPaidController = TextEditingController();

  final BillsRepository _billsRepository = BillsRepository();

  late BillType _selectedType; // Track selected bill type

  late PaymentStatus _selectedStatus; // Track selected payment status

  @override
  void initState() {
    super.initState();
    if (widget.bill != null) {
      _selectedType = widget.bill!.type;
      _companyController.text = widget.bill!.company;
      _amountController.text = widget.bill!.amount.toString();
      _dueDateController.text = DateFormat('yyyy-MM-dd').format(widget.bill!.dueDate);
      _selectedStatus = widget.bill!.status;
      _notesController.text = widget.bill!.notes ?? '';
      if (widget.bill!.amountPaid != null) {
        _amountPaidController.text = widget.bill!.amountPaid!.toStringAsFixed(2);
      }
    } else {
      _selectedType = BillType.other; // Default value
      _selectedStatus = PaymentStatus.unknown; // Default value
    }
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final bill = Bill(
      id: widget.bill?.id,
      billId: widget.bill?.billId,
      company: _companyController.text,
      type: _selectedType,
      amount: double.parse(_amountController.text),
      dueDate: DateTime.parse(_dueDateController.text),
      status: _selectedStatus,
      notes: _notesController.text,
      amountPaid: widget.bill?.amountPaid,
    );

    if (widget.bill == null) {
      await _billsRepository.create(bill);
    } else {
      await _billsRepository.update(bill);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _companyController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    _notesController.dispose();
    _amountPaidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.bill != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Bill' : 'Add Bill'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (!isEditing)
                DropdownButtonFormField<BillType>(
                  initialValue: _selectedType,
                  decoration: const InputDecoration(labelText: 'Bill Type'),
                  items: BillType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.name[0].toUpperCase() + type.name.substring(1)),
                    );
                  }).toList(),
                  onChanged: (type) {
                    if (type != null) {
                      setState(() {
                        _selectedType = type;
                      });
                    }
                  },
                )
              else
                TextFormField(
                  initialValue: _selectedType.name[0].toUpperCase() + _selectedType.name.substring(1),
                  decoration: const InputDecoration(labelText: 'Bill Type'),
                  enabled: false,
                ),
              TextFormField(
                controller: _companyController,
                decoration: const InputDecoration(labelText: 'Company'),
                validator:
                    (value) => value!.isEmpty ? 'Enter company name' : null,
              ),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? 'Enter amount' : null,
              ),
              TextFormField(
                controller: _dueDateController,
                decoration: const InputDecoration(
                  labelText: 'Due Date (YYYY-MM-DD)',
                ),
                keyboardType: TextInputType.datetime,
                validator: (value) => value!.isEmpty ? 'Enter due date' : null,
              ),
              DropdownButtonFormField<PaymentStatus>(
                  initialValue: _selectedStatus,
                  decoration: const InputDecoration(labelText: 'Payment Status'),
                  items: PaymentStatus.values.map((status) {
                    return DropdownMenuItem(
                      value: status,
                      child: Text(status.name[0].toUpperCase() + status.name.substring(1)),
                    );
                  }).toList(),
                  onChanged: (status) {
                    if (status != null) {
                      setState(() {
                        _selectedStatus = status;
                      });
                    }
                  },
                ),
              TextFormField(
                controller: _amountPaidController,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Amount Paid \$'),
              ),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveBill,
                child: const Text('Save Bill'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
