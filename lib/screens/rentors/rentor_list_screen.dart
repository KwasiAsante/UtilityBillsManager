import 'package:flutter/material.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/screens/rentors/add_edit_rentor_screen.dart';
import 'package:utility_bills_manager/helpers/rentors/rentors_helper.dart';

import '../../data/models/rentor.dart';

class RentorListScreen extends StatefulWidget {
  const RentorListScreen({super.key});

  @override
  State<RentorListScreen> createState() => _RentorListScreenState();
}

class _RentorListScreenState extends State<RentorListScreen> {
  final RentorsHelper _rentorsHelper = RentorsHelper();
  Future<List<Rentor>>? _rentors;
  bool _loading = true;
  String _selectedStort = 'Percentage';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRentors();
  }

  void _loadRentors() async {
    List<Rentor> fetchedRentors = List.empty();

    Result<List<Rentor>> result = await _rentorsHelper.readAllRentors();

    if (result.isSuccess) {
      fetchedRentors = result.data!;

      if (_searchQuery.isNotEmpty) {
        fetchedRentors =
            fetchedRentors
                .where(
                  (rentor) => rentor.name.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ),
                )
                .toList();
      }

      setState(() {
        switch (_selectedStort) {
          case 'Percentage':
            {
              fetchedRentors.sort((a, b) => a.defaultPercentage.compareTo(b.defaultPercentage));
              break;
            }
          case 'Amount Paid (Lowest)':
            {
              fetchedRentors.sort((a, b) => a.amountPaid!.compareTo(b.amountPaid!));
              break;
            }
          case 'Amount Paid (Highest)':
            {
              fetchedRentors.sort((a, b) => b.amountPaid!.compareTo(a.amountPaid!));
              break;
            }
          case 'Last Payment Date (Asc)':
            {
              fetchedRentors.sort((a, b) => a.lastPaymentDate!.compareTo(b.lastPaymentDate!));
              break;
            }
          case 'Last Payment Date (Desc)':
            {
              fetchedRentors.sort((a, b) => b.lastPaymentDate!.compareTo(a.lastPaymentDate!));
              break;
            }
        }

        _rentors = Future.value(fetchedRentors);
        _loading = false;
      });
    }
    else {
      _rentors = Future.error(result.errorMessage as Object);
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rentors'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name...',
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
                _loadRentors();
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
                _loadRentors();
              },
            ),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _selectedStort,
            items:
                [
                  'Percentage',
                  'Amount Owed (Lowest)',
                  'Amount Owed (Highest)',
                  'Amount Paid (Lowest)',
                  'Amount Paid (Highest)',
                  'Last Payment Date (Asc)',
                  'Last Payment Date (Desc)',
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
                _loadRentors();
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          :FutureBuilder<List<Rentor>>(
        future: _rentors,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No rentors found.'));
          }

          final rentors = snapshot.data!;
          return ListView.builder(
            physics: AlwaysScrollableScrollPhysics(),
            itemCount: rentors.length,
            itemBuilder: (context, index) {
              final rentor = rentors[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: ListTile(
                  title: Text(rentor.name),
                  subtitle: Text(
                    'Percentage: \$${rentor.defaultPercentage}%\nAmount Paid: \$${rentor.amountPaid != null ? rentor.amountPaid!.toStringAsFixed(2) : "0"}\nLast Payment Date: ${rentor.lastPaymentDate != null ? rentor.lastPaymentDate! : "N/A"}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddEditRentorScreen(rentor: rentor),
                          ),
                        );
                        if (result == true) {
                          _loadRentors();
                        }
                      } else if (value == 'delete') {
                        await _rentorsHelper.deleteRentor(rentor.id!);
                        _loadRentors();
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
            MaterialPageRoute(builder: (context) => const AddEditRentorScreen()),
          );
          if (result == true) {
            _loadRentors();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
