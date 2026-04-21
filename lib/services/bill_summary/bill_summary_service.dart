import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';

/// Singleton service for rentor bill summary messaging.
///
/// All methods are pure (no I/O) — callers supply the bills list and an
/// optional [DateTime] for the current time so the service is fully testable
/// without mocking.
class BillSummaryService {
  static final BillSummaryService _instance = BillSummaryService._internal();

  factory BillSummaryService() => _instance;

  BillSummaryService._internal();

  /// Returns the subset of [allBills] that are eligible for [rentor]'s
  /// summary this month (as determined by [now], defaulting to [DateTime.now]).
  ///
  /// A bill is eligible when ALL of the following are true:
  /// 1. [bill.status] is not [PaymentStatus.paid] — `unpaid`, `partial`, and
  ///    `unknown` statuses all count as eligible.
  /// 2. [bill.type] is not in [rentor.excludedBillTypes].
  /// 3. [bill.dueDate] falls in the current calendar month — OR, for
  ///    [BillType.water] only, in the following month (water bills arrive
  ///    mid-month but are due early next month).
  List<Bill> getEligibleBills(
    Rentor rentor,
    List<Bill> allBills, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final nextMonth = ref.month == 12 ? 1 : ref.month + 1;
    final nextYear = ref.month == 12 ? ref.year + 1 : ref.year;

    return allBills.where((bill) {
      if (bill.status == PaymentStatus.paid) return false;
      if (rentor.excludedBillTypes.contains(bill.type)) return false;

      final dueThisMonth =
          bill.dueDate.year == ref.year && bill.dueDate.month == ref.month;
      final dueNextMonthWater = bill.type == BillType.water &&
          bill.dueDate.year == nextYear &&
          bill.dueDate.month == nextMonth;

      return dueThisMonth || dueNextMonthWater;
    }).toList();
  }

  /// Returns `true` when [eligibleBills] is empty — the rentor owes nothing
  /// this month.
  bool isSettledForMonth(List<Bill> eligibleBills) => eligibleBills.isEmpty;

  /// Generates a bill summary message for [rentor] from [selectedBills].
  ///
  /// [now] defaults to [DateTime.now] and is used to determine the greeting
  /// and the average due-date month for regular bills. Pass it explicitly in
  /// tests to get deterministic output.
  ///
  /// Format:
  /// - Regular bills only:
  ///   "{greeting} {firstName}, the electric bill is $X and gas bill is $Y due April 15th."
  /// - With water:
  ///   "{greeting} {firstName}, the electric bill is $X due April 15th. The water bill is $Y due May 1st."
  /// - Water only:
  ///   "{greeting} {firstName}, the water bill is $Y due May 1st."
  String generateMessage(
    Rentor rentor,
    List<Bill> selectedBills, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final greeting = _greeting(ref.hour);
    final firstName = rentor.name.split(' ').first;

    if (selectedBills.isEmpty) return '';

    final waterBills =
        selectedBills.where((b) => b.type == BillType.water).toList();
    final regularBills =
        selectedBills.where((b) => b.type != BillType.water).toList();

    // Sum owed amount per bill type for regular bills.
    final Map<BillType, double> regularOwed = {};
    for (final bill in regularBills) {
      final owed = Rentor.calculateOwedAmount(rentor, bill);
      regularOwed.update(bill.type, (v) => v + owed, ifAbsent: () => owed);
    }

    String message = '$greeting $firstName';
    final hasRegular = regularOwed.isNotEmpty;

    if (hasRegular) {
      final avgDay =
          (regularBills.map((b) => b.dueDate.day).reduce((a, b) => a + b) /
                  regularBills.length)
              .round();
      final avgDate = DateTime(ref.year, ref.month, avgDay);
      final billList = _formatBillList(regularOwed.entries.toList());
      message += ', $billList due ${_formatDate(avgDate)}.';
    }

    if (waterBills.isNotEmpty) {
      final waterOwed = waterBills.fold(
          0.0, (sum, b) => sum + Rentor.calculateOwedAmount(rentor, b));
      final waterDate = waterBills.first.dueDate;
      final waterAmount = '\$${waterOwed.toStringAsFixed(2)}';
      final waterDue = _formatDate(waterDate);
      if (hasRegular) {
        message += ' The water bill is $waterAmount due $waterDue.';
      } else {
        message += ', the water bill is $waterAmount due $waterDue.';
      }
    }

    return message;
  }

  String _greeting(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Formats [date] as "Month Dayth" — e.g. "April 15th", "May 1st".
  String _formatDate(DateTime date) {
    final day = date.day;
    return '${_monthName(date.month)} $day${_ordinalSuffix(day)}';
  }

  String _ordinalSuffix(int day) {
    // 11–13 are exceptions: always "th"
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  String _monthName(int month) {
    const months = [
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
    return months[month - 1];
  }

  /// Formats a list of (BillType → owed amount) entries as a human-readable
  /// bill list:
  /// - 1 item:  "the electric bill is $45.00"
  /// - 2 items: "the electric bill is $45.00 and gas bill is $30.00"
  /// - 3+items: "the electric bill is $45.00, gas bill is $30.00, and internet bill is $25.00"
  ///
  /// [BillType.name] returns capitalized names ("Electric", "Gas", etc.).
  /// They are lowercased here for message text.
  String _formatBillList(List<MapEntry<BillType, double>> entries) {
    if (entries.isEmpty) return '';

    String formatEntry(MapEntry<BillType, double> e, bool isFirst) {
      final typeName = e.key.name.toLowerCase();
      final amount = e.value.toStringAsFixed(2);
      return '${isFirst ? 'the ' : ''}$typeName bill is \$$amount';
    }

    if (entries.length == 1) return formatEntry(entries[0], true);
    if (entries.length == 2) {
      return '${formatEntry(entries[0], true)} and ${formatEntry(entries[1], false)}';
    }

    final parts = [formatEntry(entries[0], true)];
    for (int i = 1; i < entries.length - 1; i++) {
      parts.add(formatEntry(entries[i], false));
    }
    parts.add('and ${formatEntry(entries[entries.length - 1], false)}');
    return parts.join(', ');
  }
}
