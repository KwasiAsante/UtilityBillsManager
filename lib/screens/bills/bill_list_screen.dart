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
import 'package:utility_bills_manager/services/email/google_account_service.dart';

import '../../data/models/bill.dart';

class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key});

  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends State<BillListScreen> {
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

  final BillsHelper _billsHelper = BillsHelper();
  final EmailDataHelper _emailDataHelper = EmailDataHelper();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  Future<List<Bill>>? _bills;
  List<Bill> _allBills = [];
  bool _loading = true;
  bool _isListScrollable = false;
  String _selectedFilter = 'All';
  String _selectedStort = 'Due Date (Latest)';
  int? _selectedDueYear;
  int? _selectedDueMonth;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _initGoogleSignInForWeb();
    } else {
      _loadBills(syncEmails: true);
    }
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

    if (!GoogleAccountService().isInitialized) {
      _loading = false;
      await GoogleAccountService().initialize(
        onSignedIn: () => _loadBills(syncEmails: true),
      );
    }

    if (GoogleAccountService().isAuthenticated &&
        GoogleAccountService().isSignedIn) {
      await _loadBills(syncEmails: true);
    }
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

  Future<void> _authorizeGoogleAccount() async {
    await GoogleAccountService().authorize();

    if (!mounted) return;

    if (GoogleAccountService().isAuthorized) {
      await _loadBills(syncEmails: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gmail access authorized.')));
    } else {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gmail authorization was not granted.')),
      );
    }
  }

  void _showAuthorizationRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Authorize Gmail access before syncing bills.'),
      ),
    );
  }

  Future<void> _syncBills() async {
    if (kIsWeb && !GoogleAccountService().isAuthorized) {
      _showAuthorizationRequiredMessage();
      return;
    }

    await _loadBills(syncEmails: true);
  }

  Widget _buildWebGoogleAction() {
    final googleAccountService = GoogleAccountService();

    if (googleAccountService.isSignedIn) {
      if (googleAccountService.isAuthorized) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Tooltip(
            message: 'Gmail access authorized',
            child: Icon(Icons.mark_email_read),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: _authorizeGoogleAccount,
            icon: const Icon(Icons.lock_open),
            label: const Text('Authorize Gmail'),
          ),
        ),
      );
    }

    return Padding(
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
    );
  }

  DateTime? _parseDueDate(Bill bill) {
    return DateTime.tryParse(bill.dueDate);
  }

  List<int> _getAvailableDueYears() {
    final years = <int>{};
    for (final bill in _allBills) {
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
                          _updateDisplayedBills();
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

  void _updateDisplayedBills() {
    var displayedBills =
        _allBills.where((bill) {
          final dueDate = _parseDueDate(bill);
          final matchesFilter =
              _selectedFilter == 'All' ||
              PaymentStatusExtension.getName(bill.status) == _selectedFilter;
          final matchesSearch =
              _searchQuery.isEmpty ||
              bill.company.toLowerCase().contains(_searchQuery.toLowerCase());
          final matchesYear =
              _selectedDueYear == null ||
              (dueDate != null && dueDate.year == _selectedDueYear);
          final matchesMonth =
              _selectedDueMonth == null ||
              (dueDate != null && dueDate.month == _selectedDueMonth);
          return matchesFilter && matchesSearch && matchesYear && matchesMonth;
        }).toList();

    switch (_selectedStort) {
      case 'Due Date (Earliest)':
        displayedBills.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        break;
      case 'Due Date (Latest)':
        displayedBills.sort((a, b) => b.dueDate.compareTo(a.dueDate));
        break;
      case 'Amount (Lowest)':
        displayedBills.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case 'Amount (Highest)':
        displayedBills.sort((a, b) => b.amount.compareTo(a.amount));
        break;
    }

    setState(() {
      _bills = Future.value(displayedBills);
      _loading = false;
    });
  }

  Future<void> _loadBills({bool syncEmails = false}) async {
    setState(() {
      _loading = true;
    });

    if (syncEmails && (!kIsWeb || GoogleAccountService().isAuthorized)) {
      await _emailDataHelper.fetchBillEmails(maxEmails: 50);
    }

    final Result<List<Bill>> result = await _billsHelper.readAllBills();

    if (!mounted) return;

    if (result.isSuccess) {
      _allBills = result.data!;
      _updateDisplayedBills();
    } else {
      setState(() {
        _bills = Future.error(result.errorMessage as Object);
        _loading = false;
      });
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
                _updateDisplayedBills();
              },
            ),
          ),
        ),
        actions: [
          if (kIsWeb) _buildWebGoogleAction(),
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
                _updateDisplayedBills();
              },
            ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                });
                _updateDisplayedBills();
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
                _updateDisplayedBills();
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
                _updateDisplayedBills();
              }
            },
          ),
          if (!_isListScrollable)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _syncBills();
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
                    if (!kIsWeb ||
                        (GoogleAccountService().isSignedIn &&
                            GoogleAccountService().isAuthorized)) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    } else {
                      return Center(
                        child: Text(
                          'Please sign in to your Google account to view bills.',
                        ),
                      );
                    }
                  }

                  final bills = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: () async {
                      await Future.delayed(Duration(seconds: 2));
                      await _syncBills();
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
