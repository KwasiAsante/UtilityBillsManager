import 'package:flutter/material.dart';
import 'package:utility_bills_manager/data/database/database_helper.dart';
import 'package:utility_bills_manager/data/models/bill.dart';

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
  final _statusController = TextEditingController();
  final _notesController = TextEditingController();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    if (widget.bill != null) {
      _companyController.text = widget.bill!.company;
      _amountController.text = widget.bill!.amount.toString();
      _dueDateController.text = widget.bill!.dueDate;
      _statusController.text = widget.bill!.status;
      _notesController.text = widget.bill!.notes ?? '';
    }
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final bill = Bill(
      id: widget.bill?.id,
      company: _companyController.text,
      amount: double.parse(_amountController.text),
      dueDate: _dueDateController.text,
      status: _statusController.text,
      notes: _notesController.text,
    );

    if (widget.bill == null) {
      await _dbHelper.insertBill(bill);
    } else {
      await _dbHelper.updateBill(bill);
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
    _statusController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bill == null ? 'Add Bill' : 'Edit Bill'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
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
              TextFormField(
                controller: _statusController,
                decoration: const InputDecoration(
                  labelText: 'Status (Paid/Unpaid)',
                ),
                validator: (value) => value!.isEmpty ? 'Enter status' : null,
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
