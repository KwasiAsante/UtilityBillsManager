import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';

/// Stateless helper that computes how much a [Rentor] owes for a bill or a
/// list of bills based on their configured split percentages.
class BillCalculator {
  /// Returns the amount [rentor] owes for a single [bill].
  ///
  /// Uses [Rentor.billPercentages] for a type-specific override, falling back
  /// to [Rentor.defaultPercentage] if no override is set.
  static double calculateOwedAmount(Rentor rentor, Bill bill) {
    final custom = rentor.billPercentages[bill.type];
    final percent = custom ?? rentor.defaultPercentage;
    return bill.amount * percent;
  }

  /// Returns the total amount [rentor] owes across all [bills], accumulated via
  /// [calculateOwedAmount].
  static double calculateTotalOwed(Rentor rentor, List<Bill> bills) {
    return bills.fold(0.0, (total, bill) =>
      total + calculateOwedAmount(rentor, bill));
  }
}