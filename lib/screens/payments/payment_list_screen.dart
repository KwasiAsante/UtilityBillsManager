import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

import '../../data/models/payment.dart';
import '../../data/models/result.dart';
import '../../helpers/email/email_data_helper.dart';
import '../../helpers/payments/payments_helper.dart';
import '../../services/email/google_account_service.dart';
import 'add_edit_payment_screen.dart';

class PaymentListScreen extends StatefulWidget {
  const PaymentListScreen({super.key, required this.isVisible});

  final bool isVisible;

  @override
  State<PaymentListScreen> createState() => _PaymentListScreenState();
}

class _PaymentListScreenState extends State<PaymentListScreen> {
  static const String _listenerKey = 'PaymentListScreen';

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

  final PaymentsHelper _paymentsHelper = PaymentsHelper();
  final EmailDataHelper _emailDataHelper = EmailDataHelper();
  final ScrollController _scrollController = ScrollController();
  Future<List<Payment>>? _payments;
  List<Payment> _allPayments = [];
  bool _loading = true;
  bool _isSignedInListenerAttached = false;
  bool _isListScrollable = false;
  String _selectedFilter = 'All';
  String _selectedStort = 'Payment Date (Latest)';
  int? _selectedPaymentYear;
  int? _selectedPaymentMonth;
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
    if (kIsWeb) {
      _initGoogleSignInForWeb();
    } else {
      _loadPayments(syncEmails: true);
    }

    if (widget.isVisible) {
      _subscribeToSignedInEvents();
    }

    _scrollController.addListener(_checkScrollability);
  }

  @override
  void didUpdateWidget(covariant PaymentListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isVisible && widget.isVisible) {
      _subscribeToSignedInEvents();
    } else if (oldWidget.isVisible && !widget.isVisible) {
      _unsubscribeFromSignedInEvents();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromSignedInEvents();
    _scrollController.removeListener(_checkScrollability);
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeToSignedInEvents() {
    if (_isSignedInListenerAttached && GoogleAccountService().isSubscribedToSignIn(_listenerKey)) return;
    GoogleAccountService().onSignedIn(
      _listenerKey,
      () => _loadPayments(syncEmails: true),
    );
    _isSignedInListenerAttached = true;
  }

  void _unsubscribeFromSignedInEvents() {
    if (!_isSignedInListenerAttached || !GoogleAccountService().isSubscribedToSignIn(_listenerKey)) return;
    GoogleAccountService().offSignedIn(_listenerKey);
    _isSignedInListenerAttached = false;
  }

  Future<void> _initGoogleSignInForWeb() async {
    if (!kIsWeb) return;

    if (!GoogleAccountService().isInitialized) {
      _loading = false;
    }

    if (GoogleAccountService().isAuthenticated &&
        GoogleAccountService().isSignedIn) {
      await _loadPayments(syncEmails: true);
    }
  }

  Future<void> _authorizeGoogleAccount() async {
    await GoogleAccountService().authorize();

    if (!mounted) return;

    if (GoogleAccountService().isAuthorized) {
      await _loadPayments(syncEmails: true);
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
        content: Text('Authorize Gmail access before syncing payments.'),
      ),
    );
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
      else {
        if (mounted) {
          setState(() {
            _payments = Future.value([]);
            _allPayments = [];
          });
        }
      }
      if (mounted) {
        _loadPayments();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All payments deleted.')),
        );
      }
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

  Future<void> _syncPayments() async {
    if (kIsWeb && !GoogleAccountService().isAuthorized) {
      _showAuthorizationRequiredMessage();
      return;
    }

    await _loadPayments(syncEmails: true);
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

  DateTime? _parsePaymentDate(Payment payment) {
    return payment.paymentDate != null ? DateTime.tryParse(payment.paymentDate!) : null;
  }

  List<int> _getAvailablePaymentYears() {
    final years = <int>{};
    for (final payment in _allPayments) {
      final paymentDate = _parsePaymentDate(payment);
      if (paymentDate != null) {
        years.add(paymentDate.year);
      }
    }

    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }

    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    return sortedYears;
  }

  bool get _hasActivePaymentDateFilter =>
      _selectedPaymentYear != null || _selectedPaymentMonth != null;

  String _buildPaymentDateFilterTooltip() {
    final yearLabel = _selectedPaymentYear?.toString() ?? 'All years';
    final monthLabel =
    _selectedPaymentMonth == null
        ? 'All months'
        : _monthNames[_selectedPaymentMonth! - 1];
    return 'Payment date filter: $yearLabel, $monthLabel';
  }

  Future<void> _openPaymentDateFilterSheet() async {
    int? tempYear = _selectedPaymentYear;
    int? tempMonth = _selectedPaymentMonth;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableYears = _getAvailablePaymentYears();
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
                    'Payment Date Filters',
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
                            _selectedPaymentYear = tempYear;
                            _selectedPaymentMonth = tempMonth;
                          });
                          _updateDisplayedPayments();
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

  void _updateDisplayedPayments() {
    var displayedPayments =
    _allPayments.where((payment) {
      final paymentDate = _parsePaymentDate(payment);
      final matchesYear =
          _selectedPaymentYear == null ||
              (paymentDate != null && paymentDate.year == _selectedPaymentYear);
      final matchesMonth =
          _selectedPaymentMonth == null ||
              (paymentDate != null && paymentDate.month == _selectedPaymentMonth);
      return matchesYear && matchesMonth;
    }).toList();

    switch (_selectedStort) {
      case 'Payment Date (Earliest)':
        displayedPayments.sort((a, b) => _compareNullable(a.paymentDate, b.paymentDate));
        break;
      case 'Payment Date (Latest)':
        displayedPayments.sort((a, b) => _compareNullable(b.paymentDate, a.paymentDate));
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

  Future<void> _loadPayments({bool syncEmails = false}) async {
    setState(() {
      _loading = true;
    });

    if (syncEmails && (!kIsWeb || GoogleAccountService().isAuthorized)) {
      await _emailDataHelper.fetchPaymentEmails(maxEmails: 50);
    }

    final Result<List<Payment>> result = await _paymentsHelper.readAllPayments(include: { 'bill': true, 'rentor': true });

    if (!mounted) return;

    if (result.isSuccess) {
      _allPayments = result.data!;
      _updateDisplayedPayments();
    } else {
      setState(() {
        _payments = Future.error(result.errorMessage as Object);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        // bottom: PreferredSize(
        //   preferredSize: const Size.fromHeight(60),
        //   child: Padding(
        //     padding: const EdgeInsets.all(8.0),
        //     child: TextField(
        //       decoration: InputDecoration(
        //         hintText: 'Search by company...',
        //         prefixIcon: const Icon(Icons.search),
        //         border: OutlineInputBorder(
        //           borderRadius: BorderRadius.circular(10),
        //         ),
        //         filled: true,
        //         fillColor: Colors.white,
        //         contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        //       ),
        //       onChanged: (query) {
        //         setState(() {
        //           _searchQuery = query;
        //         });
        //         _updateDisplayedPayments();
        //       },
        //     ),
        //   ),
        // ),
        actions: [
          if (kIsWeb) _buildWebGoogleAction(),
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
                _updateDisplayedPayments();
              }
            },
          ),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _selectedStort,
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
                  _selectedStort = newValue;
                });
                _updateDisplayedPayments();
              }
            },
          ),
          if (!_isListScrollable)
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
      body:
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
                (GoogleAccountService().isSignedIn &&
                    GoogleAccountService().isAuthorized)) {
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
                itemCount: payments.length,
                itemBuilder: (context, index) {
                  final payment = payments[index];
                  return Card(
                    margin: const EdgeInsets.all(8.0),
                    child: ListTile(
                      title: Text(payment.bills == null || payment.bills!.isEmpty
                          ? "${payment.rentorName} - Payment Date: ${payment.paymentDate}"
                          : payment.billNames()),
                      subtitle:Text(payment.bills != null && payment.bills!.isNotEmpty
                          ? 'Paid By: ${payment.rentorName}\n'
                          'Amount Paid: \$${payment.amountPaid.toStringAsFixed(2)}\n'
                          'Payment Date: ${payment.paymentDate}'
                          : 'Amount Paid: \$${payment.amountPaid.toStringAsFixed(2)}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) =>
                                    AddEditPaymentScreen(payment: payment),
                              ),
                            );
                            if (result == true) {
                              _loadPayments();
                            }
                          } else if (value == 'delete') {
                            await _paymentsHelper.deletePayment(payment.paymentId!);
                            _loadPayments();
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
            MaterialPageRoute(builder: (context) => const AddEditPaymentScreen()),
          );
          if (result == true) {
            _loadPayments();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}