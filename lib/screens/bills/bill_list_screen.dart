import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';
import 'package:google_sign_in_web/web_only.dart' as web;
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/helpers/email/email_data_helper.dart';
import 'package:utility_bills_manager/screens/bills/add_edit_bill_screen.dart';
import 'package:utility_bills_manager/helpers/bills/bills_helper.dart';

import '../../data/models/bill.dart';

class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key});

  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends State<BillListScreen> {
  final BillsHelper _billsHelper = BillsHelper();
  final EmailDataHelper _emailDataHelper = EmailDataHelper();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  Future<List<Bill>>? _bills;
  bool _loading = true;
  bool _isListScrollable = false;
  String _selectedFilter = 'All';
  String _selectedStort = 'Due Date (Earliest)';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initGoogleSignInForWeb();
    _loadBills();
    _scrollController.addListener(_checkScrollability);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _scrollController.removeListener(_checkScrollability);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initGoogleSignInForWeb() async {
    if (!kIsWeb) return;

    final GoogleSignIn googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize(
      clientId:
          '910862354798-fm2ttlkjnv5nscsqrsqm0ieou2lva2ub.apps.googleusercontent.com',
    );

    _authSubscription = googleSignIn.authenticationEvents.listen(
      (GoogleSignInAuthenticationEvent event) async {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          await _emailDataHelper.fetchBillEmails(maxEmails: 50);
          await _loadBills();
        }
      },
    );
  }

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

  Future<void> _loadBills() async {
    _loading = true;
    List<Bill> fetchedBills = List.empty();

    await _emailDataHelper.fetchBillEmails(maxEmails: 50);

    Result<List<Bill>> result =
        _selectedFilter == 'All'
            ? await _billsHelper.readAllBills()
            : await _billsHelper.readBillsByStatus(_selectedFilter);

    if (result.isSuccess) {
      fetchedBills = result.data!;

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
        _loading = false;
      });
    } else {
      _bills = Future.error(result.errorMessage as Object);
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills'),
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
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: SizedBox(
                height: 36,
                child: web.renderButton(
                  configuration: GSIButtonConfiguration(
                    theme: GSIButtonTheme.filledBlack,
                    text: GSIButtonText.continueWith,
                  ),
                ),
              ),
            ),
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
          if (!_isListScrollable)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                _loading = true;
                _loadBills();
              },
            ),
          const SizedBox(width: 16),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : FutureBuilder<List<Bill>>(
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
                  return RefreshIndicator(
                    onRefresh: () async {
                      await Future.delayed(Duration(seconds: 2));
                      await _loadBills();
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
                        itemCount: bills.length,
                        itemBuilder: (context, index) {
                          final bill = bills[index];
                          return Card(
                            margin: const EdgeInsets.all(8.0),
                            child: ListTile(
                              title: Text(bill.company),
                              subtitle: Text(
                                'Type: ${bill.type.name}\nAmount: \$${bill.amount.toStringAsFixed(2)}\nDue Date: ${bill.dueDate}\nStatus: ${PaymentStatusExtension.getName(bill.status)}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) =>
                                                AddEditBillScreen(bill: bill),
                                      ),
                                    );
                                    if (result == true) {
                                      _loadBills();
                                    }
                                  } else if (value == 'delete') {
                                    await _billsHelper.deleteBill(bill.id!);
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
                      ),
                    ),
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
