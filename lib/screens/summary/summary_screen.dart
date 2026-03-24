import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/helpers/bills/bills_helper.dart';
import 'package:utility_bills_manager/helpers/email/email_data_helper.dart';
import 'package:utility_bills_manager/helpers/payments/payments_helper.dart';
import 'package:utility_bills_manager/helpers/rentors/rentors_helper.dart';
import 'package:utility_bills_manager/utils/export_utils.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final BillsHelper _billsHelper = BillsHelper();
  final RentorsHelper _rentorsHelper = RentorsHelper();
  final PaymentsHelper _paymentsHelper = PaymentsHelper();
  final EmailDataHelper _emailDataHelper = EmailDataHelper();

  List<Bill> _bills = [];
  List<Rentor> _rentors = [];

  String _statusFilter = 'All';

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final billsResult = await _billsHelper.readAllBills();
    final rentorsResult = await _rentorsHelper.readAllRentors();
    
    if (billsResult.isSuccess && rentorsResult.isSuccess) {
      final bills = billsResult.data!;
      final rentors = rentorsResult.data!;
      setState(() {
        _bills = bills;
        _rentors = rentors;
        _loading = false;
      });
    }
    else {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Data'),
        content: const Text(
          'This will permanently delete all emails, bills, and payments from the database.\n\n'
          'This action cannot be undone. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    final emailDeleteResult = await _emailDataHelper.deleteAllEmails();
    final paymentsDeleteResult = await _paymentsHelper.deleteAllPayments();
    final billsDeleteResult = await _billsHelper.deleteAllBills();

    final List<String> errors = [];
    if (emailDeleteResult.isError) {
      errors.add(
        emailDeleteResult.errorMessage ??
            'Failed to delete all emails.',
      );
    }
    if (paymentsDeleteResult.isError) {
      errors.add(
        paymentsDeleteResult.errorMessage ??
            'Failed to delete all payments.',
      );
    }
    if (billsDeleteResult.isError) {
      errors.add(
        billsDeleteResult.errorMessage ??
            'Failed to delete all bills.',
      );
    }

    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errors.isEmpty
                ? 'All data has been deleted.'
                : 'Delete failed: ${errors.join(' | ')}',
          ),
          backgroundColor: errors.isEmpty ? null : Colors.red,
        ),
      );
    }
  }

  double _calculateRentorShare(Bill bill, Rentor rentor) {
    final typeKey = bill.type;
    final percentage = rentor.billPercentages[typeKey] ?? 0.0;
    return bill.amount * (percentage / 100);
  }

  List<Bill> get _filteredBills {
    if (_statusFilter == 'All') return _bills;
    return _bills.where((bill) => bill.status.name == _statusFilter.toLowerCase()).toList();
  }

  void _exportToCSV() async {
    ExportUtils.exportBillsToCSV(_filteredBills, _rentors);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exported to CSV')),
      );
    }
  }

  void _exportToPDF() async {
    ExportUtils.exportBillsToPDF(_filteredBills, _rentors);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exported to PDF')),
      );
    }
  }

  Widget _buildSummaryCard(String title, List<Bill> bills) {
    final total = bills.fold(0.0, (sum, b) => sum + b.amount);
    final paid = bills
        .where((b) => b.status == PaymentStatus.paid)
        .fold(0.0, (sum, b) => sum + b.amount);
    final unpaid = total - paid;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Total: \$${total.toStringAsFixed(2)}'),
            Text('Paid: \$${paid.toStringAsFixed(2)}'),
            Text('Unpaid: \$${unpaid.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            const Text('Rentor Contributions:'),
            ..._rentors.map((r) {
              final share = bills.fold(0.0,
                  (sum, b) => sum + _calculateRentorShare(b, r));
              return Text('${r.name}: \$${share.toStringAsFixed(2)}');
            })
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlySummary() {
    final Map<String, List<Bill>> grouped = {};
    for (var bill in _filteredBills) {
      final month = DateFormat.yMMM().format(DateTime.parse(bill.dueDate));
      grouped.putIfAbsent(month, () => []).add(bill);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries
          .map((entry) => _buildSummaryCard(entry.key, entry.value))
          .toList(),
    );
  }

  Widget _buildBillTypeSummary() {
    final Map<String, List<Bill>> grouped = {};
    for (var bill in _filteredBills) {
      final type = bill.type.name;
      grouped.putIfAbsent(type, () => []).add(bill);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries
          .map((entry) => _buildSummaryCard(entry.key, entry.value))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Monthly'),
            Tab(text: 'Bill Type'),
          ],
        ),
        actions: [
          DropdownButton<String>(
            value: _statusFilter,
            onChanged: (value) => setState(() => _statusFilter = value!),
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All')),
              DropdownMenuItem(value: 'Paid', child: Text('Paid')),
              DropdownMenuItem(value: 'Unpaid', child: Text('Unpaid')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _exportToCSV,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: _exportToPDF,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            tooltip: 'Delete All Data',
            onPressed: _deleteAllData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMonthlySummary(),
                _buildBillTypeSummary(),
              ],
            ),
    );
  }
}