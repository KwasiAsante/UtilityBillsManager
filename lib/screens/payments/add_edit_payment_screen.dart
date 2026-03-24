import 'package:flutter/material.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/helpers/payments/payments_helper.dart';

class AddEditPaymentScreen extends StatefulWidget {
  final Payment? payment;

  const AddEditPaymentScreen({super.key, this.payment});

  @override
  State<StatefulWidget> createState() {
    return _AddEditPaymentScreenState();
  }
}

class _AddEditPaymentScreenState extends State<AddEditPaymentScreen> {
  // final _formKey = GlobalKey<FormState>();
  // final _companyController = TextEditingController();
  // final _amountController = TextEditingController();
  // final _dueDateController = TextEditingController();
  // final _notesController = TextEditingController();
  //
  // final PaymentsHelper _billsHelper = PaymentsHelper();
  //
  // late PaymentStatus _selectedStatus; // Track selected payment status

  @override
  void initState() {
    super.initState();
    // if (widget.payment != null) {
    //   _selectedType = widget.payment!.type;
    //   _companyController.text = widget.payment!.company;
    //   _amountController.text = widget.payment!.amount.toString();
    //   _dueDateController.text = widget.payment!.dueDate;
    //   _selectedStatus = widget.payment!.status;
    //   _notesController.text = widget.payment!.notes ?? '';
    // } else {
    //   _selectedType = PaymentType.other; // Default value
    //   _selectedStatus = PaymentStatus.unknown; // Default value
    // }
  }

  // Future<void> _savePayment() async {
  //   if (!_formKey.currentState!.validate()) {
  //     return;
  //   }
  //
  //   final payment = Payment(
  //     id: widget.payment?.id,
  //     company: _companyController.text,
  //     type: _selectedType,
  //     amount: double.parse(_amountController.text),
  //     dueDate: _dueDateController.text,
  //     status: _selectedStatus,
  //     notes: _notesController.text,
  //   );
  //
  //   if (widget.payment == null) {
  //     await _billsHelper.createPayment(payment);
  //   } else {
  //     await _billsHelper.updatePayment(payment);
  //   }
  //
  //   if (mounted) {
  //     Navigator.pop(context, true);
  //   }
  // }

  @override
  void dispose() {
    // _companyController.dispose();
    // _amountController.dispose();
    // _dueDateController.dispose();
    // _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.payment != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Add Payment' : 'Edit Payment'),
      ),
      // body: Padding(
      //   padding: const EdgeInsets.all(16.0),
      //   child: Form(
      //     key: _formKey,
      //     child: Column(
      //       children: [
      //         if (!isEditing)
      //           DropdownButtonFormField<PaymentType>(
      //             initialValue: _selectedType,
      //             decoration: const InputDecoration(labelText: 'Payment Type'),
      //             items: PaymentType.values.map((type) {
      //               return DropdownMenuItem(
      //                 value: type,
      //                 child: Text(type.name[0].toUpperCase() + type.name.substring(1)),
      //               );
      //             }).toList(),
      //             onChanged: (type) {
      //               if (type != null) {
      //                 setState(() {
      //                   _selectedType = type;
      //                 });
      //               }
      //             },
      //           )
      //         else
      //           TextFormField(
      //             initialValue: _selectedType.name[0].toUpperCase() + _selectedType.name.substring(1),
      //             decoration: const InputDecoration(labelText: 'Payment Type'),
      //             enabled: false,
      //           ),
      //         TextFormField(
      //           controller: _companyController,
      //           decoration: const InputDecoration(labelText: 'Company'),
      //           validator:
      //               (value) => value!.isEmpty ? 'Enter company name' : null,
      //         ),
      //         TextFormField(
      //           controller: _amountController,
      //           decoration: const InputDecoration(labelText: 'Amount'),
      //           keyboardType: TextInputType.number,
      //           validator: (value) => value!.isEmpty ? 'Enter amount' : null,
      //         ),
      //         TextFormField(
      //           controller: _dueDateController,
      //           decoration: const InputDecoration(
      //             labelText: 'Due Date (YYYY-MM-DD)',
      //           ),
      //           keyboardType: TextInputType.datetime,
      //           validator: (value) => value!.isEmpty ? 'Enter due date' : null,
      //         ),
      //         DropdownButtonFormField<PaymentStatus>(
      //           initialValue: _selectedStatus,
      //           decoration: const InputDecoration(labelText: 'Payment Status'),
      //           items: PaymentStatus.values.map((status) {
      //             return DropdownMenuItem(
      //               value: status,
      //               child: Text(status.name[0].toUpperCase() + status.name.substring(1)),
      //             );
      //           }).toList(),
      //           onChanged: (status) {
      //             if (status != null) {
      //               setState(() {
      //                 _selectedStatus = status;
      //               });
      //             }
      //           },
      //         ),
      //         TextFormField(
      //           controller: _notesController,
      //           decoration: const InputDecoration(
      //             labelText: 'Notes (Optional)',
      //           ),
      //         ),
      //         const SizedBox(height: 20),
      //         ElevatedButton(
      //           onPressed: _savePayment,
      //           child: const Text('Save Payment'),
      //         ),
      //       ],
      //     ),
      //   ),
      // ),
    );
  }
}
