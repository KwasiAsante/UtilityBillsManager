import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'add_edit_bill_screen.dart';
import '../../config/app_config.dart';
import '../../config/server_configuration.dart';
import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/bills_repository.dart';
import '../../helpers/email/email_data_helper.dart';
import '../../screens/base/google_sign_in_screen_state.dart';
import '../../utils/constants.dart';
import '../../utils/dialogs/due_date_filter_sheet.dart';
import '../../utils/dialogs/sync_options_dialog.dart';
import '../../widgets/notification_bell_icon.dart';
import '../../widgets/settings_icon_button.dart';

/// Screen that displays the list of utility bills.
///
/// Supports status filtering, due-date filtering (year / month / custom range),
/// full-text search, and sorting.  On web it extends
/// [GoogleSignInScreenState] to gate email sync behind a Gmail sign-in,
/// and on mobile / desktop it triggers an IMAP fetch directly.
class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key, required this.isVisible});

  /// Controls visibility — passed from the [IndexedStack] in [MainTabScreen]
  /// to avoid unnecessary background work when the tab is not active.
  final bool isVisible;

  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends GoogleSignInScreenState<BillListScreen> {
  //region GoogleSignInScreenState contract
  @override
  String get googleListenerKey => 'BillListScreen';

  @override
  Future<void> onGoogleSignedIn({bool canSync = true}) async {
    await _loadBills(
      syncEmails: canSync,
      earliestEmailDate: ServerConfiguration.emailEarliestDate,
    );
  }

  @override
  void onWebGoogleNotInitialized() {
    setState(() => _loading = false);
  }
  //endregion

  final BillsRepository _billsRepository = BillsRepository();
  final EmailDataHelper _emailDataHelper = EmailDataHelper();
  final ScrollController _scrollController = ScrollController();

  Future<List<Bill>>? _bills;
  List<Bill> _allBills = [];
  bool _loading = true;
  bool _isListScrollable = false;
  String _selectedFilter = 'All';
  String _selectedSort = 'Due Date (Latest)';
  int? _selectedDueYear;
  int? _selectedDueMonth;
  DateTime? _dateRangeStart;
  DateTime? _dateRangeEnd;
  String _searchQuery = '';

  //region Lifecycle
  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_checkScrollability);
    _billsRepository.addListener(_onBillsUpdated);

    if (isGoogleSignInEnabled) {
      if (widget.isVisible) {
        subscribeToSignedInEvents();
      }

      initGoogleSignInForWeb();
    } else if (widget.isVisible) {
      _loadBills(
        syncEmails: !kIsWeb && AppConfig.mode == AppMode.server,
        earliestEmailDate: ServerConfiguration.emailEarliestDate,
      );
    }
  }

  @override
  void didUpdateWidget(covariant BillListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isGoogleSignInEnabled) {
      if (!oldWidget.isVisible && widget.isVisible) {
        subscribeToSignedInEvents();
      } else if (oldWidget.isVisible && !widget.isVisible) {
        unsubscribeFromSignedInEvents();
      }
    }
  }

  @override
  void dispose() {
    unsubscribeFromSignedInEvents();
    _billsRepository.removeListener(_onBillsUpdated);
    _scrollController.removeListener(_checkScrollability);
    _scrollController.dispose();
    super.dispose();
  }

  void _onBillsUpdated() {
    if (!mounted) return;
    if (_billsRepository.lastError != null) {
      setState(() {
        _bills = Future.error(_billsRepository.lastError!);
        _loading = false;
      });
    } else {
      _allBills = _billsRepository.bills;
      _updateDisplayedBills();
    }
  }
  //endregion

  //region Bills
  Future<void> _syncBills() async {
    if (isGoogleSignInEnabled && !googleAccountService.isAuthorized) {
      googleAccountService.showAuthorizationRequiredMessage(context);
      return;
    }

    final options = await SyncOptionsDialog.show(context);
    if (options == null) return;

    await _loadBills(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      maxEmails: options.maxEmails,
    );
  }

  Future<void> _loadBills({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    int maxEmails = 50,
  }) async {
    setState(() => _loading = true);

    if (syncEmails) {
      if (shouldAbortWebSync('bills')) {
        setState(() => _loading = false);
        return;
      }

      await _emailDataHelper.syncBillEmails(
        earliestEmailDate: earliestEmailDate,
        maxEmails: maxEmails,
      );
    }

    if (!mounted) return;
    await _billsRepository.reload();
  }

  Future<void> _deleteAllBills() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete All Bills'),
            content: const Text(
              'Are you sure you want to delete all bills? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      final result = await _billsRepository.deleteAll();
      if (result.isError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting bills: ${result.errorMessage}'),
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All bills deleted.')));
      }
    }
  }

  void _updateDisplayedBills() {
    var displayedBills =
        _allBills.where((bill) {
          final dueDate = bill.dueDate;
          final matchesFilter =
              _selectedFilter == 'All' ||
              PaymentStatusExtension.getName(bill.status) == _selectedFilter;
          final matchesSearch =
              _searchQuery.isEmpty ||
              bill.company.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              bill.companyName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              );
          final matchesYear =
              _selectedDueYear == null || (dueDate.year == _selectedDueYear);
          final matchesMonth =
              _selectedDueMonth == null || (dueDate.month == _selectedDueMonth);
          final matchesDateRange =
              (_dateRangeStart == null && _dateRangeEnd == null) ||
              ((_dateRangeStart == null ||
                      !dueDate.isBefore(_dateRangeStart!)) &&
                  (_dateRangeEnd == null || !dueDate.isAfter(_dateRangeEnd!)));
          return matchesFilter &&
              matchesSearch &&
              matchesYear &&
              matchesMonth &&
              matchesDateRange;
        }).toList();

    switch (_selectedSort) {
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
  //endregion

  //region Date Filtering
  List<int> _getAvailableDueYears() {
    final years = <int>{};
    for (final bill in _allBills) {
      years.add(bill.dueDate.year);
    }

    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }

    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    return sortedYears;
  }

  bool get _hasActiveDueDateFilter =>
      _selectedDueYear != null ||
      _selectedDueMonth != null ||
      _dateRangeStart != null ||
      _dateRangeEnd != null;

  String _buildDueDateFilterTooltip() {
    if (_dateRangeStart != null || _dateRangeEnd != null) {
      final start =
          _dateRangeStart != null
              ? DueDateFilterSheet.formatDate(_dateRangeStart!)
              : 'Any';
      final end =
          _dateRangeEnd != null
              ? DueDateFilterSheet.formatDate(_dateRangeEnd!)
              : 'Any';
      return 'Date range: $start – $end';
    }
    final yearLabel = _selectedDueYear?.toString() ?? 'All years';
    final monthLabel =
        _selectedDueMonth == null
            ? 'All months'
            : AppConstants.monthNames[_selectedDueMonth! - 1];
    return 'Due date filter: $yearLabel, $monthLabel';
  }

  Future<void> _openDueDateFilterSheet() async {
    final result = await DueDateFilterSheet.show(
      context,
      availableYears: _getAvailableDueYears(),
      current: DueDateFilterResult(
        selectedYear: _selectedDueYear,
        selectedMonth: _selectedDueMonth,
        dateRangeStart: _dateRangeStart,
        dateRangeEnd: _dateRangeEnd,
      ),
    );
    if (result == null) return;
    setState(() {
      _selectedDueYear = result.selectedYear;
      _selectedDueMonth = result.selectedMonth;
      _dateRangeStart = result.dateRangeStart;
      _dateRangeEnd = result.dateRangeEnd;
    });
    _updateDisplayedBills();
  }
  //endregion

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
          const NotificationBellIcon(),
          if (isGoogleSignInEnabled)
            googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
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
                  _dateRangeStart = null;
                  _dateRangeEnd = null;
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
            value: _selectedSort,
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
                  _selectedSort = newValue;
                });
                _updateDisplayedBills();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _syncBills,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Delete all bills',
            onPressed: _deleteAllBills,
          ),
          const SizedBox(width: 16),
          const SettingsIconButton(),
        ],
      ),
      body: Column(
        children: [
          if (isGoogleSignInEnabled &&
              googleAccountService.buildWebWarningBanner() != null)
            googleAccountService.buildWebWarningBanner()!,
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : FutureBuilder<List<Bill>>(
                      future: _bills,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        } else if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        } else if (!snapshot.hasData ||
                            snapshot.data!.isEmpty) {
                          if (!isGoogleSignInEnabled ||
                              (googleAccountService.isSignedIn &&
                                  googleAccountService.isAuthorized)) {
                            return const Center(
                              child: Text(
                                'No bills found. Pull down or click on the Refresh button to sync with Gmail or click the + button to add a bill.',
                              ),
                            );
                          } else {
                            return const Center(
                              child: Text(
                                'Please sign in to your Google account to view bills.',
                              ),
                            );
                          }
                        }

                        final bills = snapshot.data!;
                        return RefreshIndicator(
                          onRefresh: () async {
                            await Future.delayed(const Duration(seconds: 2));
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
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: bills.length,
                              itemBuilder: (context, index) {
                                final bill = bills[index];
                                return Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    isThreeLine: true,
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  AddEditBillScreen(bill: bill),
                                        ),
                                      );
                                    },
                                    title: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            bill.companyName,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '\$${bill.amount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${bill.type.name[0].toUpperCase()}${bill.type.name.substring(1)}  ·  Due ${DateFormat('MMM d, yyyy').format(bill.dueDate)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _buildStatusBadge(bill.status),
                                        ],
                                      ),
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (context) =>
                                                      AddEditBillScreen(
                                                        bill: bill,
                                                      ),
                                            ),
                                          );
                                        } else if (value == 'delete') {
                                          await _billsRepository.delete(
                                            bill.billId,
                                          );
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
                                              textStyle: TextStyle(
                                                color: Colors.red,
                                              ),
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'bill_list_fab',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddEditBillScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatusBadge(PaymentStatus status) {
    final Color bgColor;
    final Color textColor;
    switch (status) {
      case PaymentStatus.paid:
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case PaymentStatus.partial:
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      default:
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        PaymentStatusExtension.getName(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
