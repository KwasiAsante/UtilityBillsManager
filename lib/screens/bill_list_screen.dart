import 'package:flutter/material.dart';
import 'package:utility_bills_manager/data/database/database_helper.dart';
import 'package:utility_bills_manager/screens/add_edit_bill_screen.dart';

import '../data/models/bill.dart';

class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key});

  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends State<BillListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  Future<List<Bill>>? _bills;
  String _selectedFilter = 'All';
  String _selectedStort = 'Due Date (Earliest)';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  void _loadBills() async {
    List<Bill> fetchedBills =
        _selectedFilter == 'All'
            ? await _dbHelper.getAllBills()
            : await _dbHelper.getBillsByStatus(_selectedFilter);

    if (_searchQuery.isNotEmpty) {
      fetchedBills =
          fetchedBills
              .where(
                (bill) => bill.company.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              )
              .toList();
    }

    setState(() {
      switch (_selectedStort) {
        case 'Due Date (Earliest)':
          {
            fetchedBills.sort((a, b) => a.dueDate.compareTo(b.dueDate));
            break;
          }
        case 'Due Date (Latest)':
          {
            fetchedBills.sort((a, b) => b.dueDate.compareTo(a.dueDate));
            break;
          }
        case 'Amount (Lowest)':
          {
            fetchedBills.sort((a, b) => a.amount.compareTo(b.amount));
            break;
          }
        case 'Amount (Highest)':
          {
            fetchedBills.sort((a, b) => b.amount.compareTo(a.amount));
            break;
          }
      }

      _bills = Future.value(fetchedBills);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Utility Bills'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by company...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
                _loadBills();
              },
            ),
          ),
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                });
                _loadBills();
              },
            ),
          DropdownButton<String>(
            value: _selectedFilter,
            items:
                ['All', 'Paid', 'Unpaid'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedFilter = newValue;
                });
                _loadBills();
              }
            },
          ),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _selectedStort,
            items:
                [
                  'Due Date (Earliest)',
                  'Due Date (Latest)',
                  'Amount (Lowest)',
                  'Amount (Highest)',
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedStort = newValue;
                });
                _loadBills();
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: FutureBuilder<List<Bill>>(
        future: _bills,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No bills found.'));
          }

          final bills = snapshot.data!;
          return ListView.builder(
            itemCount: bills.length,
            itemBuilder: (context, index) {
              final bill = bills[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: ListTile(
                  title: Text(bill.company),
                  subtitle: Text(
                    'Amount: \$${bill.amount.toStringAsFixed(2)}\nDue Date: ${bill.dueDate}\nStatus: ${bill.status}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddEditBillScreen(bill: bill),
                          ),
                        );
                        if (result == true) {
                          _loadBills();
                        }
                      } else if (value == 'delete') {
                        await _dbHelper.deleteBill(bill.id!);
                        _loadBills();
                      }
                    },
                    itemBuilder:
                        (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddEditBillScreen()),
          );
          if (result == true) {
            _loadBills();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
