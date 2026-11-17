import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import 'property_manager_share.dart';

/// The outcome of recalculating one bill: what it should now say it has been
/// paid, and the status that goes with it.
class BillRecalculation {
  const BillRecalculation({
    required this.bill,
    required this.amountPaid,
    required this.status,
  });

  /// The bill as it is now, untouched.
  final Bill bill;

  /// The amount paid its payments actually cover, rounded to cents.
  final double amountPaid;

  /// The status that goes with [amountPaid]; never lower than [Bill.status]
  /// when that is `paid`.
  final PaymentStatus status;

  /// Whether [amountPaid] (compared in cents) or [status] differs from [bill].
  bool get changed =>
      _cents(amountPaid) != _cents(bill.amountPaid) || status != bill.status;

  /// A new [Bill] with every field of [bill] copied and the new [amountPaid]
  /// and [status] applied.
  Bill toUpdatedBill() => _copyBill(bill, amountPaid, status);
}

/// A shortfall on a bill: every rentor who owes on it has paid something, yet
/// the Property Manager is covering more than their own share.
class BillGap {
  const BillGap({
    required this.billAmount,
    required this.paid,
    required this.owed,
  });

  /// The bill's full amount.
  final double billAmount;

  /// The amount paid toward the bill so far.
  final double paid;

  /// The sum of the rentors' whole-dollar shares of the bill.
  final double owed;

  /// What the Property Manager is covering right now.
  double get covering => billAmount - paid;

  /// What the Property Manager would cover if the rentors had paid in full.
  double get expectedCovering => billAmount - owed;

  /// A plain-language description of the gap.
  String get message =>
      'Rentors paid \$${paid.toStringAsFixed(2)} of '
      '\$${owed.toStringAsFixed(2)} owed. '
      'The Property Manager is covering \$${covering.toStringAsFixed(2)} '
      'instead of \$${expectedCovering.toStringAsFixed(2)}.';
}

/// Sets each bill's amount paid to what its assigned payments actually cover.
///
/// Every payment pays the bills it lists oldest-due-first, each capped at the
/// paying rentor's whole-dollar share of that bill. Money left over once every
/// listed bill is covered stays unassigned.
///
/// Pure and dependency-free beyond the models.
class BillPaymentRecalculator {
  BillPaymentRecalculator._();

  /// Recalculates [bill] from the [payments] that list it.
  ///
  /// [bills] and [rentors] are needed because each payment is spread over all
  /// the bills it lists. Returns `null` when [bill] must not be touched: its
  /// status is `unknown`, or no payment from a known rentor lists it.
  static BillRecalculation? recalculate(
    Bill bill,
    List<Payment> payments,
    List<Bill> bills,
    List<Rentor> rentors,
  ) {
    final listing =
        payments
            .where((p) => p.billIds?.contains(bill.billId) ?? false)
            .toList();
    final totals = _totals(listing, bills, rentors);
    final total = totals[bill.billId];
    return total == null ? null : _result(bill, total, rentors);
  }

  /// Recalculates every touchable bill in [bills], one entry per bill whether
  /// or not it changed. Bills that [recalculate] would skip are left out.
  static List<BillRecalculation> recalculateAll(
    List<Bill> bills,
    List<Payment> payments,
    List<Rentor> rentors,
  ) {
    final totals = _totals(payments, bills, rentors);
    return [
      for (final bill in bills)
        if (totals[bill.billId] != null)
          _result(bill, totals[bill.billId]!, rentors),
    ];
  }

  /// The [BillGap] on [bill], or `null` when there is none.
  ///
  /// There is a gap only when [bill] is neither `paid` nor `unknown`, at least
  /// one rentor owes on it (whole-dollar share above zero), every such rentor
  /// has a payment that lists it, and it still isn't considered paid once the
  /// Property Manager's share and rounding tolerance are allowed for.
  static BillGap? gapFor(
    Bill bill,
    List<Payment> payments,
    List<Rentor> rentors,
  ) {
    if (bill.status == PaymentStatus.paid ||
        bill.status == PaymentStatus.unknown) {
      return null;
    }
    var owed = 0.0;
    var anyOwes = false;
    for (final rentor in rentors) {
      final share = Rentor.calculateOwedAmount(
        rentor,
        bill,
        roundToWholeDollar: true,
      );
      if (share <= 0) continue;
      anyOwes = true;
      final hasPaid = payments.any(
        (p) =>
            p.rentorId == rentor.rentorId &&
            (p.billIds?.contains(bill.billId) ?? false),
      );
      if (!hasPaid) return null;
      owed += share;
    }
    if (!anyOwes || PropertyManagerShare.isConsideredPaid(bill, rentors)) {
      return null;
    }
    return BillGap(
      billAmount: bill.amount,
      paid: PropertyManagerShare.paidAmount(bill),
      owed: owed,
    );
  }

  /// billId -> total credited across [payments], for every touchable bill that
  /// a payment from a known rentor lists (0 when the money ran out before it).
  static Map<String, double> _totals(
    List<Payment> payments,
    List<Bill> bills,
    List<Rentor> rentors,
  ) {
    final billsById = {for (final b in bills) b.billId: b};
    final rentorsById = {for (final r in rentors) r.rentorId: r};
    final totals = <String, double>{};
    for (final payment in payments) {
      if (!rentorsById.containsKey(payment.rentorId)) continue;
      for (final id in payment.billIds ?? const <String>[]) {
        final bill = billsById[id];
        if (bill != null && bill.status != PaymentStatus.unknown) {
          totals.putIfAbsent(id, () => 0);
        }
      }
      _creditsFrom(payment, billsById, rentorsById).forEach((id, credit) {
        totals[id] = totals[id]! + credit;
      });
    }
    return totals;
  }

  // For one payment: billId -> credit. Skips payments whose rentor is unknown.
  static Map<String, double> _creditsFrom(
    Payment payment,
    Map<String, Bill> billsById,
    Map<String, Rentor> rentorsById,
  ) {
    final rentor = rentorsById[payment.rentorId];
    if (rentor == null) return const {};
    final bills =
        (payment.billIds ?? const <String>[])
            .map((id) => billsById[id])
            .whereType<Bill>()
            .where((b) => b.status != PaymentStatus.unknown)
            .toList()
          ..sort((a, b) {
            final byDue = a.dueDate.compareTo(b.dueDate);
            return byDue != 0 ? byDue : a.billId.compareTo(b.billId);
          });
    var left = payment.amountPaid;
    final credits = <String, double>{};
    for (final b in bills) {
      final owed = Rentor.calculateOwedAmount(
        rentor,
        b,
        roundToWholeDollar: true,
      );
      if (owed <= 0) continue;
      final credit = left < owed ? left : owed;
      if (credit <= 0) break;
      credits[b.billId] = (credits[b.billId] ?? 0) + credit;
      left -= credit;
    }
    return credits;
  }

  static BillRecalculation _result(
    Bill bill,
    double total,
    List<Rentor> rentors,
  ) {
    final amountPaid = _cents(total) / 100;
    var status = PropertyManagerShare.recomputeStatus(
      _copyBill(bill, amountPaid, bill.status),
      rentors,
    );
    // A recalculation never moves a bill down from paid.
    if (bill.status == PaymentStatus.paid) status = PaymentStatus.paid;
    return BillRecalculation(
      bill: bill,
      amountPaid: amountPaid,
      status: status,
    );
  }
}

int _cents(double? amount) => ((amount ?? 0) * 100).round();

Bill _copyBill(Bill bill, double amountPaid, PaymentStatus status) => Bill(
  id: bill.id,
  billId: bill.billId,
  company: bill.company,
  type: bill.type,
  amount: bill.amount,
  dueDate: bill.dueDate,
  status: status,
  notes: bill.notes,
  amountPaid: amountPaid,
);
