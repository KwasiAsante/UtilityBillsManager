import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:utility_bills_manager/data/repositories/rentors_repository.dart';
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
  final RentorsRepository _rentorsRepository = RentorsRepository();
  final ScrollController _scrollController = ScrollController();

  Future<List<Rentor>>? _rentors;
  List<Rentor> _allRentors = [];
  bool _loading = true;
  bool _isListScrollable = false;
  String _selectedStort = 'Percentage';
  String _searchQuery = '';

  int _compareNullable<T extends Comparable<T>>(
    T? a,
    T? b, {
    bool descending = false,
  }) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    final comparison = a.compareTo(b);
    return descending ? -comparison : comparison;
  }

  @override
  void initState() {
    super.initState();
    _rentorsRepository.addListener(_onRentorsUpdated);
    _rentorsRepository.reload();
    _scrollController.addListener(_checkScrollability);
  }

  @override
  void dispose() {
    _rentorsRepository.removeListener(_onRentorsUpdated);
    _scrollController.removeListener(_checkScrollability);
    _scrollController.dispose();
    super.dispose();
  }

  void _onRentorsUpdated() {
    if (!mounted) return;
    if (_rentorsRepository.lastError != null) {
      setState(() {
        _rentors = Future.error(_rentorsRepository.lastError!);
        _loading = false;
      });
    } else {
      _allRentors = _rentorsRepository.rentors;
      _updateDisplayedRentors();
    }
  }

  void _updateDisplayedRentors() {
    var displayed = _allRentors.where((rentor) =>
      _searchQuery.isEmpty ||
      rentor.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();

    switch (_selectedStort) {
      case 'Percentage':
        displayed.sort((a, b) => a.defaultPercentage.compareTo(b.defaultPercentage));
        break;
      case 'Last Payment Date (Asc)':
        displayed.sort((a, b) => _compareNullable(a.lastPaymentDate, b.lastPaymentDate));
        break;
      case 'Last Payment Date (Desc)':
        displayed.sort((a, b) => _compareNullable(a.lastPaymentDate, b.lastPaymentDate, descending: true));
        break;
    }

    setState(() {
      _rentors = Future.value(displayed);
      _loading = false;
    });
  }

  Future<void> _deleteAllRentors() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Rentors'),
        content: const Text(
          'Are you sure you want to delete all rentors? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final rentor in _allRentors) {
        await _rentorsHelper.deleteRentor(rentor.rentorId);
      }

      await _rentorsRepository.reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All rentors deleted.')),
        );
      }
    }
  }

  //region Scroll
  void _checkScrollability() {
    if (_scrollController.hasClients) {
      final isScrollable = _scrollController.position.maxScrollExtent > 0;
      if (isScrollable != _isListScrollable) {
        setState(() {
          _isListScrollable = isScrollable;
        });
      }
    }
  }
  //endregion

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
                _updateDisplayedRentors();
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
                _updateDisplayedRentors();
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _rentorsRepository.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Delete all rentors',
            onPressed: _deleteAllRentors,
          ),
          const SizedBox(width: 16),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _selectedStort,
            items:
                [
                  'Percentage',
                  'Amount Owed (Lowest)',
                  'Amount Owed (Highest)',
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
                _updateDisplayedRentors();
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
            return const Center(child: Text('No rentors found. Pull down or click on the Refresh button to sync or click the + button to add a rentor.'));
          }

          final rentors = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              await Future.delayed(Duration(seconds: 2));
              await _rentorsRepository.reload();
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                },
              ),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: rentors.length,
                itemBuilder: (context, index) {
                  final rentor = rentors[index];
                  return Card(
                    margin: const EdgeInsets.all(8.0),
                    child: ListTile(
                      title: Text(rentor.name),
                      subtitle: Text(
                        'Percentage: \$${rentor.defaultPercentage}%\nLast Payment Date: ${rentor.lastPaymentDate != null ? rentor.lastPaymentDate! : "N/A"}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AddEditRentorScreen(rentor: rentor),
                              ),
                            );
                          } else if (value == 'delete') {
                            await _rentorsRepository.delete(rentor.rentorId);
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
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddEditRentorScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
