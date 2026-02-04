import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';

class BillCalculator {
  static double calculateOwedAmount(Rentor rentor, Bill bill) {
    final custom = rentor.billPercentages[bill.type];
    final percent = custom ?? rentor.defaultPercentage;
    return bill.amount * percent;
  }

  static double calculateTotalOwed(Rentor rentor, List<Bill> bills) {
    return bills.fold(0.0, (total, bill) =>
      total + calculateOwedAmount(rentor, bill));
  }
}