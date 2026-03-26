import 'package:flutter/material.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/helpers/payments/payments_helper.dart';
import 'package:utility_bills_manager/helpers/rentors/rentors_helper.dart';

import '../../data/models/bill.dart';
import '../../helpers/bills/bills_helper.dart';

class AddEditPaymentScreen extends StatefulWidget {
  final Payment? payment;

  const AddEditPaymentScreen({super.key, this.payment});

  @override
  State<StatefulWidget> createState() {
    return _AddEditPaymentScreenState();
  }
}

class _AddEditPaymentScreenState extends State<AddEditPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountPaidController = TextEditingController();
  final _paymentDateController = TextEditingController();
  final _rentorController = TextEditingController();
  final Map<String, TextEditingController> _billControllers = {};

  final PaymentsHelper _paymentsHelper = PaymentsHelper();
  final RentorsHelper _rentorsHelper = RentorsHelper();
  final BillsHelper _billsHelper = BillsHelper();

  Rentor? _selectedRentor;
  List<Rentor> _allRentors = [];

  List<Bill> _selectedBills = [];
  List<Bill> _allBills = [];

  @override
  void initState() {
    super.initState();
    if (widget.payment != null) {
      final payment = widget.payment!;
      _amountPaidController.text = payment.amountPaid.toString();
      _paymentDateController.text = payment.paymentDate?.toString() ?? '';

      if (payment.rentor == null && payment.rentorId != null) {
        _rentorsHelper.readRentors(payment.rentorId!).then((result) {
          if (result.isSuccess) {
            setState(() {
              _selectedRentor = result.data;
              _rentorController.text = _selectedRentor?.name ?? '';
            });
          }
        });
      }
      else {
        _selectedRentor = payment.rentor;
        _rentorController.text = _selectedRentor?.name ?? '';
      }

      if (payment.billIds != null && payment.billIds!.isNotEmpty && (payment.bills == null || payment.bills!.isEmpty || payment.bills!.length < payment.billIds!.length)) {
        _billsHelper.readAllBills().then((result) {
          if (result.isSuccess) {
            final bills = result.data!;
            final paymentBills = bills.where((bill) => payment.billIds!.contains(bill.billId)).toList();
            setState(() {
              _allBills = bills;
              _selectedBills = paymentBills;
              for (var bill in _selectedBills) {
                _billControllers[bill.billId] = TextEditingController(
                  text: '${bill.type.name}: ${bill.companyName} - ${bill.dueDate}',
                );
              }
            });
          }
        });
      }
      else {
        _selectedBills = payment.bills ?? [];
        for (var bill in _selectedBills) {
          _billControllers[bill.billId] = TextEditingController(
            text: '${bill.type.name}: ${bill.companyName} - ${bill.dueDate}',
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _amountPaidController.dispose();
    _paymentDateController.dispose();
    _rentorController.dispose();
    for (var controller in _billControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  //region Rentor
  void _clearRentorSelection() {
    setState(() {
      _selectedRentor = null;
      _rentorController.clear();
    });
  }

  Future<void> _showRentorPickerDialog() async {
    if (_allRentors.isEmpty) {
      final result = await _rentorsHelper.readAllRentors();
      if (result.isSuccess) {
        setState(() {
          _allRentors = result.data!;
        });
      }
    }

    if (context.mounted)  {
      showDialog(
          context: context,
          builder: (context) => _RentorPickerDialog(
            currentSelectedRentor: _selectedRentor,
            allRentors: _allRentors,
            rentorsHelper: _rentorsHelper,
            onAdd: (Rentor? selectedRentor, List<Rentor> allRentors) {
              setState(() {
                _allRentors = allRentors;
                _selectedRentor = selectedRentor;
                if (_selectedRentor == null) {
                  _clearRentorSelection();
                }
                else {
                  _rentorController.text = selectedRentor?.name ?? '';
                }
              });
            },
          )
      );
    }
  }
  //endregion

  //region Bill
  void _addBills() {
    setState(() {
      for (var bill in _selectedBills) {
        if (!_billControllers.containsKey(bill.billId)) {
          _billControllers[bill.billId] = TextEditingController(
            text: '${bill.type.name}: ${bill.companyName} - ${bill.dueDate}',
          );
        }
      }
    });
  }

  void _removeBill(String billId) {
    setState(() {
      _selectedBills.removeWhere((bill) => bill.billId == billId);
      _billControllers[billId]?.dispose();
      _billControllers.remove(billId);
    });
  }

  void _removeAllBills() {
    setState(() {
      _selectedBills.clear();
      for (var controller in _billControllers.values) {
        controller.dispose();
      }
      _billControllers.clear();
    });
  }

  DateTime? _parsePaymentDateForBillFilter() {
    final paymentDateText = _paymentDateController.text.trim();
    if (paymentDateText.isEmpty) {
      return null;
    }

    return DateTime.tryParse(paymentDateText);
  }
  
  void _showBillSelectionDialog() {
    final paymentDate = _parsePaymentDateForBillFilter();

    showDialog(
      context: context,
      builder: (context) => _BillSelectionDialog(
        currentSelectedBills: _selectedBills,
        allBills: _allBills,
        billsHelper: _billsHelper,
        initialDueYear: paymentDate?.year,
        initialDueMonth: paymentDate?.month,
        onAdd: (selectedBills, allBills) {
          setState(() {
            _removeAllBills();

            _selectedBills = selectedBills;
            _allBills = allBills;

            if (_selectedBills.isNotEmpty) {
              _addBills();
            }
          });
        },
      ),
    );
  }

  Widget _buildBillFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Bills', style: TextStyle(fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: _showBillSelectionDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_selectedBills.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'No bills assigned to this payment.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: _selectedBills.length,
            itemBuilder: (context, index) {
              final bill = _selectedBills[index];
              final controller = _billControllers[bill.billId]!;
              final displayName = '${bill.type.name}: ${bill.companyName} - ${bill.dueDate}';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    Expanded(
                        child: TextFormField(
                          controller: controller,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: displayName,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)
                            )
                          ),
                        )
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _removeBill(bill.billId),
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: 'Remove',
                    ),
                  ]
                )
              );
            }
          )
      ],
    );
  }
  //endregion

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final payment = Payment(
      id: widget.payment?.id,
      paymentId: widget.payment?.paymentId,
      rentorId: _selectedRentor?.rentorId,
      billIds: _selectedBills.map((bill) => bill.billId).toList(),
      amountPaid: double.parse(_amountPaidController.text),
      paymentDate: _paymentDateController.text,
      rentor: _selectedRentor,
      bills: _selectedBills
    );

    if (widget.payment == null) {
      await _paymentsHelper.createPayment(payment);
    } else {
      await _paymentsHelper.updatePayment(payment);
    }

    _selectedRentor = null;
    _allRentors = [];

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.payment != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Payment' : 'Add Payment')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _amountPaidController,
                decoration: const InputDecoration(labelText: 'Amount '),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? 'Enter amount' : null,
              ),
              TextFormField(
                controller: _paymentDateController,
                decoration: const InputDecoration(
                  labelText: 'Payment Date (YYYY-MM-DD)',
                ),
                keyboardType: TextInputType.datetime,
                validator:
                    (value) => value!.isEmpty ? 'Enter payment date' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rentorController,
                readOnly: true,
                onTap: _showRentorPickerDialog,
                decoration: InputDecoration(
                  labelText: 'Assigned Rentor',
                  hintText: 'Select a rentor',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedRentor != null)
                        IconButton(
                          tooltip: 'De-assign rentor',
                          onPressed: _clearRentorSelection,
                          icon: const Icon(Icons.cancel_outlined),
                        ),
                      IconButton(
                        tooltip: 'Search rentors',
                        onPressed: _showRentorPickerDialog,
                        icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              _buildBillFields(),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _savePayment,
                child: const Text('Save Payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//region Rentor Picker Dialog
class _RentorPickerDialog extends StatefulWidget {
  final Rentor? currentSelectedRentor;
  final Function(Rentor?, List<Rentor>) onAdd;
  final List<Rentor> allRentors;
  final RentorsHelper rentorsHelper;

  const _RentorPickerDialog({
    required this.currentSelectedRentor,
    required this.allRentors,
    required this.rentorsHelper,
    required this.onAdd,
  });

  @override
  State<_RentorPickerDialog> createState() => _RentorPickerDialogState();
}

class _RentorPickerDialogState extends State<_RentorPickerDialog> {
  Rentor? selectedRentor;
  List<Rentor> allRentors = [];
  late RentorsHelper rentorsHelper;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    selectedRentor = widget.currentSelectedRentor;
    allRentors = widget.allRentors;
    rentorsHelper = widget.rentorsHelper;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredRentors = allRentors
        .where((rentor) => rentor.name.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    Rentor? selectedFilteredRentor;
    if (selectedRentor != null) {
      for (final rentor in filteredRentors) {
        if (rentor.rentorId == selectedRentor!.rentorId) {
          selectedFilteredRentor = rentor;
          break;
        }
      }
    }

    return AlertDialog(
      title: const Text('Assign Rentor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by rentor name',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value.toLowerCase().trim();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    String errorMessage = '';
                    if (allRentors.isEmpty) {
                      Result<List<Rentor>> result = await rentorsHelper.readAllRentors();
                      if (!result.isSuccess) {
                        errorMessage = result.errorMessage ?? 'Failed to load rentors.';
                      }
                      else {
                        allRentors = result.data!;
                      }
                    }

                    if (allRentors.isEmpty && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage.isEmpty ? 'No rentors available.' : errorMessage),
                        ),
                      );
                    }

                    setState(() {
                      searchQuery = '';
                    });
                  },
                  tooltip: 'Refresh rentor list',
                ),
              ],
            ),
            RadioGroup<Rentor>(
              groupValue: selectedFilteredRentor,
              onChanged: (rentor) {
                setState(() {
                  selectedRentor = rentor;
                });
              },
              child: Column(
                children: filteredRentors.map((rentor) {
                  return RadioListTile<Rentor>(
                    title: Text(rentor.name),
                    value: rentor
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20)
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onAdd(selectedRentor, allRentors);
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            selectedRentor = null;
            widget.onAdd(selectedRentor, allRentors);
            Navigator.pop(context);
          },
          child: const Text('Clear Rentor Selection'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onAdd(selectedRentor, allRentors);
            Navigator.pop(context);
          },
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
//endregion

//region Bill Selection Dialog
class _BillSelectionDialog extends StatefulWidget {
  final List<Bill> currentSelectedBills;
  final List<Bill> allBills;
  final BillsHelper billsHelper;
  final int? initialDueYear;
  final int? initialDueMonth;
  final Function(List<Bill> selectedBill, List<Bill> allBills) onAdd;

  const _BillSelectionDialog({
    required this.currentSelectedBills,
    required this.allBills,
    required this.billsHelper,
    this.initialDueYear,
    this.initialDueMonth,
    required this.onAdd,
  });

  @override
  State<_BillSelectionDialog> createState() => _BillSelectionDialogState();
}

class _BillSelectionDialogState extends State<_BillSelectionDialog> {
  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  List<Bill> selectedBills = [];
  List<Bill> allBills = [];
  late BillsHelper billsHelper;

  String searchQuery = '';
  int? _selectedDueYear;
  int? _selectedDueMonth;

  @override
  void initState() {
    super.initState();
    selectedBills = widget.currentSelectedBills.toList();
    allBills = widget.allBills.toList();
    billsHelper = widget.billsHelper;
    _selectedDueYear = widget.initialDueYear;
    _selectedDueMonth =
        widget.initialDueMonth != null &&
                widget.initialDueMonth! >= 1 &&
                widget.initialDueMonth! <= 12
            ? widget.initialDueMonth
            : null;
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _toggleSelectAll(List<Bill> filteredBills) {
    setState(() {
      final allFiltered = filteredBills.every(
              (bill) => selectedBills.any((selected) => selected.billId == bill.billId));

      if (allFiltered) {
        // Deselect all filtered bills
        for (final bill in filteredBills) {
          selectedBills.removeWhere((selected) => selected.billId == bill.billId);
        }
      } else {
        // Select all filtered bills
        for (final bill in filteredBills) {
          if (!selectedBills.any((selected) => selected.billId == bill.billId)) {
            selectedBills.add(bill);
          }
        }
      }
    });
  }

  DateTime? _parseDueDate(Bill bill) {
    return DateTime.tryParse(bill.dueDate);
  }

  List<int> _getAvailableDueYears() {
    final years = <int>{};
    for (final bill in allBills) {
      final dueDate = _parseDueDate(bill);
      if (dueDate != null) {
        years.add(dueDate.year);
      }
    }

    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }

    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    return sortedYears;
  }

  bool get _hasActiveDueDateFilter =>
      _selectedDueYear != null || _selectedDueMonth != null;

  String _buildDueDateFilterTooltip() {
    final yearLabel = _selectedDueYear?.toString() ?? 'All years';
    final monthLabel =
        _selectedDueMonth == null
            ? 'All months'
            : _monthNames[_selectedDueMonth! - 1];
    return 'Due date filter: $yearLabel, $monthLabel';
  }

  Future<void> _openDueDateFilterSheet() async {
    int? tempYear = _selectedDueYear;
    int? tempMonth = _selectedDueMonth;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableYears = _getAvailableDueYears();
            final safeYear =
                tempYear != null && availableYears.contains(tempYear)
                    ? tempYear
                    : null;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Due Date Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: safeYear,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All years'),
                      ),
                      ...availableYears.map(
                        (year) => DropdownMenuItem<int?>(
                          value: year,
                          child: Text(year.toString()),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setModalState(() {
                        tempYear = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: tempMonth,
                    decoration: const InputDecoration(labelText: 'Month'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All months'),
                      ),
                      ...List.generate(
                        12,
                        (index) => DropdownMenuItem<int?>(
                          value: index + 1,
                          child: Text(_monthNames[index]),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setModalState(() {
                        tempMonth = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            tempYear = null;
                            tempMonth = null;
                          });
                        },
                        child: const Text('Clear'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _selectedDueYear = tempYear;
                            _selectedDueMonth = tempMonth;
                          });
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredBills = allBills
        .where((bill) {
          final matchesSearch = searchQuery.isEmpty ||
              bill.company.toLowerCase().contains(searchQuery.toLowerCase()) ||
              bill.companyName.toLowerCase().contains(searchQuery.toLowerCase());
          final dueDate = _parseDueDate(bill);
          final matchesYear =
              _selectedDueYear == null ||
              (dueDate != null && dueDate.year == _selectedDueYear);
          final matchesMonth =
              _selectedDueMonth == null ||
              (dueDate != null && dueDate.month == _selectedDueMonth);
          return matchesSearch && matchesYear && matchesMonth;
        })
        .toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

    final allFilteredSelected = filteredBills.isNotEmpty &&
        filteredBills.every(
            (bill) => selectedBills.any((selected) => selected.billId == bill.billId));

    return AlertDialog(
      title: const Text('Assign Bills'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by bill name',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value.toLowerCase().trim();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: allFilteredSelected ? 'Deselect all' : 'Select all',
                  icon: Icon(
                    allFilteredSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                  ),
                  onPressed: () => _toggleSelectAll(filteredBills),
                ),
                IconButton(
                  tooltip: _buildDueDateFilterTooltip(),
                  icon: Icon(
                    _hasActiveDueDateFilter
                        ? Icons.calendar_month
                        : Icons.calendar_month_outlined,
                  ),
                  onPressed: _openDueDateFilterSheet,
                ),
                if (_hasActiveDueDateFilter)
                  IconButton(
                    tooltip: 'Clear due date filters',
                    icon: const Icon(Icons.filter_alt_off),
                    onPressed: () {
                      setState(() {
                        _selectedDueYear = null;
                        _selectedDueMonth = null;
                      });
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    String errorMessage = '';
                    if (allBills.isEmpty) {
                      Result<List<Bill>> result = await billsHelper.readAllBills();
                      if (!result.isSuccess) {
                        errorMessage = result.errorMessage ?? 'Failed to load bills.';
                      }
                      else {
                        allBills = result.data!;
                      }
                    }

                    if (allBills.isEmpty && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage.isEmpty ? 'No bills available.' : errorMessage),
                        ),
                      );
                    }

                    setState(() {
                      searchQuery = '';
                    });
                  },
                  tooltip: 'Refresh bill list',
                ),
              ],
            ),
            Column(
              children: filteredBills.map((bill) {
                final isSelected = selectedBills.any((selected) => selected.billId == bill.billId);
                return CheckboxListTile(
                  title: Text(bill.companyName),
                  subtitle: Text('Type: ${bill.type.name}\nAmount: \$${bill.amount.toStringAsFixed(2)}\nDue Date: ${bill.dueDate}\nStatus: ${PaymentStatusExtension.getName(bill.status)}'),
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        selectedBills.add(bill);
                      } else {
                        selectedBills.removeWhere((selected) => selected.billId == bill.billId);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20)
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onAdd(selectedBills, allBills);
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            selectedBills = [];
            widget.onAdd(selectedBills, allBills);
            Navigator.pop(context);
          },
          child: const Text('Clear Bill Selection'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onAdd(selectedBills, allBills);
            Navigator.pop(context);
          },
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
//endregion