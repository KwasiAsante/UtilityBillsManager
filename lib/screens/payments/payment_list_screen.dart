import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/payments_repository.dart';
import '../../helpers/email/email_data_helper.dart';
import '../../helpers/payments/payments_helper.dart';
import '../../screens/base/google_sign_in_screen_state.dart';
import '../../utils/comparable_utils.dart';
import '../../utils/constants.dart';
import '../../utils/dialogs/due_date_filter_sheet.dart';
import '../../utils/dialogs/sync_options_dialog.dart';

import 'add_edit_payment_screen.dart';

class PaymentListScreen extends StatefulWidget {
  const PaymentListScreen({super.key, required this.isVisible});

  final bool isVisible;

  @override
  State<PaymentListScreen> createState() => _PaymentListScreenState();
}

class _PaymentListScreenState extends GoogleSignInScreenState<PaymentListScreen> {
  // ---------------------------------------------------------------------------
  // GoogleSignInScreenState contract
  // ---------------------------------------------------------------------------

  @override
  String get googleListenerKey => 'PaymentListScreen';

  @override
  Future<void> onGoogleSignedIn({bool canSync = true}) async {
    await _loadPayments(
      syncEmails: canSync,
      earliestEmailDate: AppConfig.emailEarliestDate,
    );
  }

  @override
  void onWebGoogleNotInitialized() {
    setState(() => _loading = false);
  }

  // ---------------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------------

  final PaymentsHelper _paymentsHelper = PaymentsHelper();
  final PaymentsRepository _paymentsRepository = PaymentsRepository();
  final EmailDataHelper _emailDataHelper = EmailDataHelper();
  final ScrollController _scrollController = ScrollController();

  Future<List<Payment>>? _payments;
  List<Payment> _allPayments = [];
  bool _loading = true;
  bool _isListScrollable = false;
  String _selectedSort = 'Payment Date (Latest)';
  int? _selectedPaymentYear;
  int? _selectedPaymentMonth;
  DateTime? _dateRangeStart;
  DateTime? _dateRangeEnd;
  String _searchQuery = '';

  //region Lifecycle
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      initGoogleSignInForWeb();
    } else {
      _loadPayments(syncEmails: true);
    }

    if (widget.isVisible) {
      subscribeToSignedInEvents();
    }

    _scrollController.addListener(_checkScrollability);
    _paymentsRepository.addListener(_onPaymentsUpdated);
  }

  @override
  void didUpdateWidget(covariant PaymentListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isVisible && widget.isVisible) {
      subscribeToSignedInEvents();
    } else if (oldWidget.isVisible && !widget.isVisible) {
      unsubscribeFromSignedInEvents();
    }
  }

  @override
  void dispose() {
    unsubscribeFromSignedInEvents();
    _paymentsRepository.removeListener(_onPaymentsUpdated);
    _scrollController.removeListener(_checkScrollability);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPaymentsUpdated() {
    if (!mounted) return;
    if (_paymentsRepository.lastError != null) {
      setState(() {
        _payments = Future.error(_paymentsRepository.lastError!);
        _loading = false;
      });
    } else {
      _allPayments = _paymentsRepository.payments;
      _updateDisplayedPayments();
    }
  }
  //endregion

  //region Payments
  Future<void> _syncPayments() async {
    if (kIsWeb && !googleAccountService.isAuthorized) {
      googleAccountService.showAuthorizationRequiredMessage(context);
      return;
    }

    final options = await SyncOptionsDialog.show(context);
    if (options == null) return;

    await _loadPayments(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      maxEmails: options.maxEmails,
    );
  }

  Future<void> _loadPayments({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    int maxEmails = 50,
  }) async {
    setState(() {
      _loading = true;
    });

    if (syncEmails && (!kIsWeb || googleAccountService.isAuthorized)) {
      await _emailDataHelper.fetchPaymentEmails(
        earliestEmailDate: earliestEmailDate,
        maxEmails: maxEmails,
      );
    }

    if (!mounted) return;
    await _paymentsRepository.reload();
    // _onPaymentsUpdated() handles the rest via listener
  }
  
  Future<void> _deleteAllPayments() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Payments'),
        content: const Text(
          'Are you sure you want to delete all payments? This action cannot be undone.',
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
      final result = await _paymentsHelper.deleteAllPayments();
      if (result.isError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting payments: ${result.errorMessage}')),
          );
        }
        return;
      }

      await _paymentsRepository.reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All payments deleted.')),
        );
      }
    }
  }

  void _updateDisplayedPayments() {
    var displayedPayments =
    _allPayments.where((payment) {
      final paymentDate = payment.paymentDate;
      final matchesYear =
          _selectedPaymentYear == null ||
              (paymentDate.year == _selectedPaymentYear);
      final matchesMonth =
          _selectedPaymentMonth == null ||
              (paymentDate.month == _selectedPaymentMonth);
      final matchesDateRange =
          (_dateRangeStart == null && _dateRangeEnd == null) ||
              ((_dateRangeStart == null || !paymentDate.isBefore(_dateRangeStart!)) &&
                  (_dateRangeEnd == null || !paymentDate.isAfter(_dateRangeEnd!)));
      return matchesYear && matchesMonth && matchesDateRange;
    }).toList();

    switch (_selectedSort) {
      case 'Payment Date (Earliest)':
        displayedPayments.sort((a, b) => ComparableUtils.compareNullable(a.paymentDate, b.paymentDate));
        break;
      case 'Payment Date (Latest)':
        displayedPayments.sort((a, b) => ComparableUtils.compareNullable(b.paymentDate, a.paymentDate));
        break;
      case 'Amount Paid (Lowest)':
        displayedPayments.sort((a, b) => a.amountPaid.compareTo(b.amountPaid));
        break;
      case 'Amount Paid (Highest)':
        displayedPayments.sort((a, b) => b.amountPaid.compareTo(a.amountPaid));
        break;
    }

    setState(() {
      _payments = Future.value(displayedPayments);
      _loading = false;
    });
  }
  //endregion

  //region Date Filtering
  List<int> _getAvailablePaymentYears() {
    final years = <int>{};
    for (final payment in _allPayments) {
      years.add(payment.paymentDate.year);
    }

    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }

    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    return sortedYears;
  }

  bool get _hasActivePaymentDateFilter =>
      _selectedPaymentYear != null ||
          _selectedPaymentMonth != null ||
          _dateRangeStart != null ||
          _dateRangeEnd != null;

  String _buildPaymentDateFilterTooltip() {
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
    final yearLabel = _selectedPaymentYear?.toString() ?? 'All years';
    final monthLabel =
    _selectedPaymentMonth == null
        ? 'All months'
        : AppConstants.monthNames[_selectedPaymentMonth! - 1];
    return 'Due date filter: $yearLabel, $monthLabel';
  }

  Future<void> _openPaymentDateFilterSheet() async {
    final result = await DueDateFilterSheet.show(
      context,
      availableYears: _getAvailablePaymentYears(),
      current: DueDateFilterResult(
        selectedYear: _selectedPaymentYear,
        selectedMonth: _selectedPaymentMonth,
        dateRangeStart: _dateRangeStart,
        dateRangeEnd: _dateRangeEnd,
      ),
    );
    if (result == null) return;
    setState(() {
      _selectedPaymentYear = result.selectedYear;
      _selectedPaymentMonth = result.selectedMonth;
      _dateRangeStart = result.dateRangeStart;
      _dateRangeEnd = result.dateRangeEnd;
    });
    _updateDisplayedPayments();
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
        title: const Text('Payments'),
        actions: [
          if (kIsWeb) googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
          IconButton(
            tooltip: _buildPaymentDateFilterTooltip(),
            icon: Icon(
              _hasActivePaymentDateFilter
                  ? Icons.calendar_month
                  : Icons.calendar_month_outlined,
            ),
            onPressed: _openPaymentDateFilterSheet,
          ),
          if (_hasActivePaymentDateFilter)
            IconButton(
              tooltip: 'Clear payment date filters',
              icon: const Icon(Icons.filter_alt_off),
              onPressed: () {
                setState(() {
                  _selectedPaymentYear = null;
                  _selectedPaymentMonth = null;
                  _dateRangeStart = null;
                  _dateRangeEnd = null;
                });
                _updateDisplayedPayments();
              },
            ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                });
                _updateDisplayedPayments();
              },
            ),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _selectedSort,
            items:
            [
              'Payment Date (Earliest)',
              'Payment Date (Latest)',
              'Amount Paid (Lowest)',
              'Amount Paid (Highest)',
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
                _updateDisplayedPayments();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _syncPayments();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Delete all payments',
            onPressed: _deleteAllPayments,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column (
        children: [
          if (googleAccountService.buildWebWarningBanner() != null)
            googleAccountService.buildWebWarningBanner()!,
          Expanded(
            child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : FutureBuilder<List<Payment>>(
                future: _payments,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    if (!kIsWeb ||
                        (googleAccountService.isSignedIn &&
                            googleAccountService.isAuthorized)) {
                      return Center(child: Text('No payments found. Pull down or click on the Refresh button to sync with Gmail or click the + button to add a payment.'));
                    } else {
                      return Center(
                        child: Text(
                          'Please sign in to your Google account to view payments.',
                        ),
                      );
                    }
                  }

                  final payments = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: () async {
                      await Future.delayed(Duration(seconds: 2));
                      await _syncPayments();
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
                        itemCount: payments.length,
                        itemBuilder: (context, index) {
                          final payment = payments[index];
                          return Card(
                            margin: const EdgeInsets.all(8.0),
                            child: ListTile(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AddEditPaymentScreen(payment: payment),
                                  ),
                                );
                              },
                              title: Text(payment.bills == null || payment.bills!.isEmpty
                                  ? "${payment.rentorName} - Payment Date: ${payment.paymentDate}"
                                  : payment.billNames(newLine: true)),
                              subtitle:Text(payment.bills != null && payment.bills!.isNotEmpty
                                  ? 'Paid By: ${payment.rentorName}\n'
                                  'Amount Paid: \$${payment.amountPaid.toStringAsFixed(2)}\n'
                                  'Payment Date: ${payment.paymentDate}'
                                  : 'Amount Paid: \$${payment.amountPaid.toStringAsFixed(2)}'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) =>
                                            AddEditPaymentScreen(payment: payment),
                                      ),
                                    );
                                  } else if (value == 'delete') {
                                    await _paymentsRepository.delete(payment.paymentId!);
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
                                    textStyle: TextStyle(color: Colors.red),
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
                }
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddEditPaymentScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
