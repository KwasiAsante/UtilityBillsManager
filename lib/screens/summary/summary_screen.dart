import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:utility_bills_manager/utils/app_logger.dart';

import '../../data/repositories/email_data_repository.dart';
import '../base/google_sign_in_screen_state.dart';
import '../../config/server_configuration.dart';
import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../data/repositories/rentors_repository.dart';
import '../../helpers/email/email_data_helper.dart';
import '../../utils/dialogs/sync_options_dialog.dart';
import '../../utils/export_utils.dart';
import '../../widgets/notification_bell_icon.dart';
import '../../widgets/settings_icon_button.dart';

/// Screen that provides a financial overview across all bills, payments, and
/// rentors.
///
/// Presents data in two tabs (Bills and Rentors) and supports:
/// - Email sync (bill + payment emails) with a configurable date range.
/// - CSV and PDF export via [ExportUtils].
/// - Month / status breakdowns showing total, paid, and unpaid amounts.
/// - Per-rentor contribution summaries.
///
/// On web, extends [GoogleSignInScreenState] to gate email sync behind Gmail
/// authentication.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.isVisible});

  /// Controls visibility — passed from the [IndexedStack] in [MainTabScreen].
  final bool isVisible;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends GoogleSignInScreenState<SummaryScreen> with SingleTickerProviderStateMixin {
  // ── GoogleSignInScreenState contract ─────────────────────────────────────────

  @override
  String get googleListenerKey => 'SummaryScreen';

  @override
  Future<void> onGoogleSignedIn({bool canSync = true}) async {
    await _loadData(
      syncEmails: canSync,
      earliestEmailDate: ServerConfiguration.emailEarliestDate,
    );
  }

  @override
  void onWebGoogleNotInitialized() {
    setState(() => _loading = false);
  }

  late TabController _tabController;

  final BillsRepository _billsRepo = BillsRepository();
  final RentorsRepository _rentorsRepo = RentorsRepository();
  final PaymentsRepository _paymentsRepo = PaymentsRepository();
  final EmailDataRepository _emailDataRepo = EmailDataRepository();
  final EmailDataHelper _emailDataHelper = EmailDataHelper();

  List<Bill> _bills = [];
  List<Rentor> _rentors = [];
  List<Payment> _payments = [];

  Map<String, List<Payment>> _billPaymentIndex = {};

  String _statusFilter = 'All';
  bool _loading = true;

  /// When false (default): bills within the "considered paid" threshold show
  /// $0 unpaid. When true: actual unpaid amounts are always shown.
  bool _showActualUnpaid = false;

  // ── Threshold logic ──────────────────────────────────────────────────────────

  /// Returns the maximum unpaid-fraction that still counts as "considered paid"
  /// for a given bill type, or null if no threshold applies.
  static double? _unpaidThreshold(BillType type) {
    switch (type) {
      case BillType.electric:
      case BillType.gas:
      case BillType.water:
        return 0.30; // ≤30% unpaid → considered paid
      case BillType.internet:
        return 0.50; // ≤50% unpaid → considered paid
      default:
        return null;
    }
  }

  bool _isConsideredPaid(Bill bill) {
    final threshold = _unpaidThreshold(bill.type);
    if (threshold == null) return false;
    final actualUnpaid = bill.amount - _paidAmount(bill);
    if (actualUnpaid <= 0) return true;
    // Within the percentage threshold, OR within $1.00 of the threshold amount.
    final thresholdAmount = bill.amount * threshold;
    return actualUnpaid <= thresholdAmount + 1.0 || bill.status == PaymentStatus.paid;
  }

  /// The paid amount to display, respecting the toggle and threshold.
  double _displayPaid(Bill bill) {
    if (!_showActualUnpaid && _isConsideredPaid(bill)) return bill.amount;
    return _paidAmount(bill);
  }

  /// The unpaid amount to display, respecting the toggle and threshold.
  double _displayUnpaid(Bill bill) {
    if (!_showActualUnpaid && _isConsideredPaid(bill)) return 0.0;
    return bill.amount - _paidAmount(bill);
  }

  // ── Data ─────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);
    _billsRepo.addListener(_onDataChanged);
    _rentorsRepo.addListener(_onDataChanged);
    _paymentsRepo.addListener(_onDataChanged);
    _emailDataRepo.addListener(_onDataChanged);

    if (isGoogleSignInEnabled) {
      if (widget.isVisible) {
        subscribeToSignedInEvents();
      }

      initGoogleSignInForWeb();
    } else if (widget.isVisible) {
      _loadData(
        syncEmails: true,
        earliestEmailDate: ServerConfiguration.emailEarliestDate,
      );
    }
  }

  @override
  void didUpdateWidget(covariant SummaryScreen oldWidget) {
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
    _billsRepo.removeListener(_onDataChanged);
    _rentorsRepo.removeListener(_onDataChanged);
    _paymentsRepo.removeListener(_onDataChanged);
    _emailDataRepo.removeListener(_onDataChanged);
    unsubscribeFromSignedInEvents();
    _tabController.dispose();
    super.dispose();
  }

  bool _rebuildScheduled = false;

  void _onDataChanged() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) return;
      setState(() {
        _bills = _billsRepo.bills;
        _rentors = _rentorsRepo.rentors;
        _payments = _paymentsRepo.payments;
        _billPaymentIndex = _buildBillPaymentIndex(_payments);
      });
    });
  }

  Future<void> _syncData() async {
    if (isGoogleSignInEnabled && !googleAccountService.isAuthorized) {
      googleAccountService.showAuthorizationRequiredMessage(context);
      return;
    }

    final options = await SyncOptionsDialog.show(context);
    if (options == null || !mounted) return;

    await _loadData(
        syncEmails: true,
        earliestEmailDate: options.earliestDate,
        maxEmails: options.maxEmails
    );
  }

  Future<void> _loadData({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    int maxEmails = 50,
  }) async {
    setState(() => _loading = true);

    if (syncEmails) {
      if (kIsWeb) {
        if (isGoogleSignInEnabled && !googleAccountService.isAuthorized) {
          AppLogger().w('Unable to sync emails on web server without Google Sign-In authorization');
          return;
        }
        else if (!isGoogleSignInEnabled) {
          AppLogger().w('Syncing emails on web platform without Google Sign-In. Google Account implementation is being handled on the server');
        }

      } else {
        AppLogger().i('Syncing emails');
      }

      await _emailDataHelper.syncBillEmails(
        earliestEmailDate: earliestEmailDate,
        maxEmails: maxEmails,
      );

      await _emailDataHelper.syncPaymentEmails(
        earliestEmailDate: earliestEmailDate,
        maxEmails: maxEmails,
      );
    }

    await Future.wait([
      _billsRepo.reload(),
      _rentorsRepo.reload(),
      _paymentsRepo.reload(),
      _emailDataRepo.reload(),
    ]);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Map<String, List<Payment>> _buildBillPaymentIndex(List<Payment> payments) {
    final index = <String, List<Payment>>{};
    for (final payment in payments) {
      for (final billId in (payment.billIds ?? [])) {
        index.putIfAbsent(billId, () => []).add(payment);
      }
    }
    return index;
  }

  Map<String, double> _rentorPaymentsForBills(List<Bill> bills) {
    final result = <String, double>{};
    final seen = <String>{};
    for (final bill in bills) {
      for (final payment in (_billPaymentIndex[bill.billId] ?? [])) {
        if (payment.rentor != null && !seen.contains(payment.paymentId)) {
          seen.add(payment.paymentId!);
          result[payment.rentor!.name] =
              (result[payment.rentor!.name] ?? 0) + payment.amountPaid;
        }
      }
    }
    return result;
  }

  List<String> _rentorNamesForBill(Bill bill) {
    final payments = _billPaymentIndex[bill.billId] ?? [];
    final names = <String>{};
    for (final p in payments) {
      if (p.rentor != null) names.add(p.rentor!.name);
    }
    return names.toList();
  }

  // ── Raw paid helper (actual amounts, ignoring threshold) ─────────────────────

  double _paidAmount(Bill bill) {
    if (bill.status == PaymentStatus.paid) {
      return bill.amountPaid ?? bill.amount;
    } else if (bill.status == PaymentStatus.partial) {
      return bill.amountPaid ?? 0.0;
    }
    return 0.0;
  }

  // ── Grouping ─────────────────────────────────────────────────────────────────

  List<Bill> get _filteredBills {
    if (_statusFilter == 'All') return _bills;
    return _bills.where((bill) => bill.status.name == _statusFilter).toList();
  }

  Map<String, List<Bill>> _groupByMonth(List<Bill> bills) {
    final Map<String, List<Bill>> grouped = {};
    for (var bill in bills) {
      final month = DateFormat('MMMM yyyy').format(bill.dueDate);
      grouped.putIfAbsent(month, () => []).add(bill);
    }
    final sorted = grouped.entries.toList()
      ..sort((a, b) => b.value.first.dueDate.compareTo(a.value.first.dueDate));
    return Map.fromEntries(sorted);
  }

  // ── Export ───────────────────────────────────────────────────────────────────

  void _exportToCSV() async {
    try {
      await ExportUtils.exportBillsToCSV(_filteredBills, _rentors, _payments);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _exportToPDF() async {
    try {
      await ExportUtils.exportBillsToPDF(_filteredBills, _rentors, _payments);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Monthly Summary ──────────────────────────────────────────────────────────

  Widget _buildMonthlySummary() {
    final grouped = _groupByMonth(_filteredBills);
    if (grouped.isEmpty) return const Center(child: Text('No bills found.'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries.map((e) => _buildMonthCard(e.key, e.value)).toList(),
    );
  }

  Widget _buildMonthCard(String month, List<Bill> bills) {
    bills.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    final total = bills.fold(0.0, (s, b) => s + b.amount);
    final paid = bills.fold(0.0, (s, b) => s + _displayPaid(b));
    final unpaid = bills.fold(0.0, (s, b) => s + _displayUnpaid(b));

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        title: Text(month,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _summaryRow(total, paid, unpaid),
        ),
        children: [
          const Divider(height: 1),
          ...bills.map((bill) => _buildBillRow(bill)),
          _buildRentorContributions(bills),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildBillRow(Bill bill) {
    final actualUnpaid = bill.amount - _paidAmount(bill);
    final displayPaid = _displayPaid(bill);
    final displayUnpaid = _displayUnpaid(bill);
    final rentorNames = _rentorNamesForBill(bill);

    // A bill that is considered paid but still has a remainder worth showing
    final hasHiddenRemainder = _isConsideredPaid(bill) && actualUnpaid > 0.005;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: bill info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${bill.type.name} — ${bill.company}',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  'Due Date: ${DateFormat('MMM d, yyyy').format(bill.dueDate)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold),
                ),
                if (rentorNames.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Paid by: ${rentorNames.join(', ')}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold),
                  ),
                ],
                if (hasHiddenRemainder && !_showActualUnpaid) ...[
                  const SizedBox(height: 2),
                  Text(
                    '* within paid threshold',
                    style: TextStyle(fontSize: 10, color: Colors.orange[700], fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: amounts
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Bill Amount: \$${bill.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Paid: \$${displayPaid.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.bold)),
              if (displayUnpaid > 0.005)
                Text(
                  'Unpaid: \$${displayUnpaid.toStringAsFixed(2)}${hasHiddenRemainder && _showActualUnpaid ? ' *' : ''}',
                  style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bill Type Summary ────────────────────────────────────────────────────────

  Widget _buildBillTypeSummary() {
    final Map<String, List<Bill>> byType = {};
    for (var bill in _filteredBills) {
      byType.putIfAbsent(bill.type.name, () => []).add(bill);
    }
    if (byType.isEmpty) return const Center(child: Text('No bills found.'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: byType.entries.map((typeEntry) {
        final grouped = _groupByMonth(typeEntry.value);
        final typeTotal = typeEntry.value.fold(0.0, (s, b) => s + b.amount);
        final typePaid = typeEntry.value.fold(0.0, (s, b) => s + _displayPaid(b));
        final typeUnpaid = typeEntry.value.fold(0.0, (s, b) => s + _displayUnpaid(b));

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ExpansionTile(
            title: Text(typeEntry.key,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _summaryRow(typeTotal, typePaid, typeUnpaid),
            ),
            children: [
              const Divider(height: 1),
              ...grouped.entries.map((monthEntry) {
                final bills = monthEntry.value;
                bills.sort((a, b) => b.dueDate.compareTo(a.dueDate));
                final total = bills.fold(0.0, (s, b) => s + b.amount);
                final paid = bills.fold(0.0, (s, b) => s + _displayPaid(b));
                final unpaid = bills.fold(0.0, (s, b) => s + _displayUnpaid(b));

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(monthEntry.key,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              )),
                      const SizedBox(height: 6),
                      _summaryRow(total, paid, unpaid),
                      _buildRentorContributions(bills, compact: true),
                      const Divider(height: 20),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  Widget _buildRentorContributions(List<Bill> bills, {bool compact = false}) {
    final contributions = _rentorPaymentsForBills(bills);
    if (contributions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 16, 8, compact ? 0 : 16, compact ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) const Divider(height: 12),
          Text(
            'Rentor Contributions',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          ...contributions.entries.map((e) => Row(
                children: [
                  Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12))),
                  Text('\$${e.value.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              )),
        ],
      ),
    );
  }

  Widget _summaryRow(double total, double paid, double unpaid) {
    return Row(
      children: [
        _statChip('Total', total),
        const SizedBox(width: 12),
        _statChip('Paid', paid, color: Colors.green[700]),
        const SizedBox(width: 12),
        _statChip('Unpaid', unpaid, color: unpaid > 0.005 ? Colors.red : Colors.grey[600]),
      ],
    );
  }

  Widget _statChip(String label, double amount, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color),
        ),
      ],
    );
  }

  // ── Rentor Owed (current month) ──────────────────────────────────────────────

  Widget _buildRentorOwedSection() {
    if (_rentors.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final currentMonthBills = _bills
        .where((b) =>
            b.dueDate.year == now.year &&
            b.dueDate.month == now.month &&
            (b.status == PaymentStatus.unpaid || b.status == PaymentStatus.partial))
        .toList();

    // rentorId -> billId -> total already paid by that rentor
    final Map<String, Map<String, double>> rentorPaidPerBill = {};
    for (final payment in _payments) {
      if (payment.rentorId != null && payment.billIds != null) {
        final map = rentorPaidPerBill.putIfAbsent(payment.rentorId!, () => {});
        for (final billId in payment.billIds!) {
          map[billId] = (map[billId] ?? 0.0) + payment.amountPaid;
        }
      }
    }

    final monthLabel = DateFormat('MMMM yyyy').format(now);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          'Rentors Owed – $monthLabel',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        children: [
          const Divider(height: 1),
          if (currentMonthBills.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No unpaid or partial bills for the current month.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else
            ..._rentors.map((rentor) => _buildRentorOwedRow(rentor, currentMonthBills, rentorPaidPerBill)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildRentorOwedRow(
    Rentor rentor,
    List<Bill> currentMonthBills,
    Map<String, Map<String, double>> rentorPaidPerBill,
  ) {
    final Map<BillType, double> breakdown = {};
    for (final bill in currentMonthBills) {
      if (rentor.excludedBillTypes.contains(bill.type)) continue;
      final pct = rentor.billPercentages[bill.type] ?? rentor.defaultPercentage;
      final totalOwed = bill.amount * (pct / 100);
      final alreadyPaid = rentorPaidPerBill[rentor.rentorId]?[bill.billId] ?? 0.0;
      final stillOwes = (totalOwed - alreadyPaid).clamp(0.0, double.infinity);
      if (stillOwes > 0) {
        breakdown[bill.type] = (breakdown[bill.type] ?? 0.0) + stillOwes;
      }
    }

    final total = breakdown.values.fold(0.0, (sum, v) => sum + v);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(rentor.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              total > 0
                  ? Text('\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))
                  : Text('All settled',
                      style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
            ],
          ),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...breakdown.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key.name,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('\$${e.value.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                )),
          ],
          const Divider(height: 16),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Monthly'),
            Tab(text: 'By Bill Type'),
          ],
        ),
        actions: [
          const NotificationBellIcon(),
          if (isGoogleSignInEnabled)
            googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync bills & payments',
            onPressed: _loading ? null : _syncData,
          ),
          DropdownButton<String>(
            value: _statusFilter,
            underline: const SizedBox(),
            onChanged: (value) => setState(() => _statusFilter = value!),
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All')),
              DropdownMenuItem(value: 'Paid', child: Text('Paid')),
              DropdownMenuItem(value: 'Unpaid', child: Text('Unpaid')),
            ],
          ),
          IconButton(
            icon: Icon(
              _showActualUnpaid ? Icons.visibility : Icons.visibility_off,
              color: _showActualUnpaid ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: _showActualUnpaid ? 'Hide actual unpaid amounts' : 'Show actual unpaid amounts',
            onPressed: () => setState(() => _showActualUnpaid = !_showActualUnpaid),
          ),
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Export CSV',
            onPressed: _exportToCSV,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: _exportToPDF,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            tooltip: 'Delete All Data',
            onPressed: _deleteAllData,
          ),
          const SizedBox(width: 16),
          const SettingsIconButton(),
        ],
      ),
      body: Column(
        children: [
          if (isGoogleSignInEnabled && googleAccountService.buildWebWarningBanner() != null)
            googleAccountService.buildWebWarningBanner()!,
          if (!_loading) _buildRentorOwedSection(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMonthlySummary(),
                      _buildBillTypeSummary(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Data'),
        content: const Text(
          'This will permanently delete all emails, bills, and payments from the database.\n\nThis action cannot be undone. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    final emailDeleteResult = await _emailDataHelper.deleteAllEmails();
    final paymentsDeleteResult = await _paymentsRepo.deleteAll();
    final billsDeleteResult = await _billsRepo.deleteAll();

    final List<String> errors = [];
    if (emailDeleteResult.isError) {
      errors.add(emailDeleteResult.errorMessage ?? 'Failed to delete all emails.');
    }
    if (paymentsDeleteResult.isError) {
      errors.add(paymentsDeleteResult.errorMessage ?? 'Failed to delete all payments.');
    }
    if (billsDeleteResult.isError) {
      errors.add(billsDeleteResult.errorMessage ?? 'Failed to delete all bills.');
    }

    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errors.isEmpty ? 'All data has been deleted.' : 'Delete failed: ${errors.join(' | ')}',
          ),
          backgroundColor: errors.isEmpty ? null : Colors.red,
        ),
      );
    }
  }
}
