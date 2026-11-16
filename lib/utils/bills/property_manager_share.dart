import 'dart:math';

import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';

/// Computes the Property Manager's share of a bill type and derives bill
/// payment status from it.
///
/// The Property Manager share is `100 - sum(rentor percentages)` over the
/// rentors active on the relevant date. A bill is "considered paid" once the
/// unpaid remainder is no more than that share of the bill (plus a rounding
/// tolerance, see [isConsideredPaid]), since the Property Manager covers their
/// own share.
///
/// Pure and dependency-free beyond the models so it can be ported verbatim to
/// the Flutter app.
class PropertyManagerShare {
  PropertyManagerShare._();

  /// Minimum dollar tolerance applied on top of the share-based threshold.
  static const double _minTolerance = 1.0;

  /// Extra dollar tolerance per rentor covering a bill.
  ///
  /// Each rentor's payment is capped at their owed amount rounded to the
  /// nearest whole dollar ([Rentor.calculateOwedAmount]), so a rentor who pays
  /// their exact share can be credited up to $0.49 less than it. With N rentors
  /// the credited total can fall short by up to $0.49 x N; $0.50 per rentor
  /// absorbs that.
  static const double _tolerancePerRentor = 0.5;

  /// The Property Manager's percentage (0-100 scale, never rounded, may be
  /// <= 0) of a [type] bill dated [asOf].
  ///
  /// Only rentors active on [asOf] count. Returns `null` when the type is not
  /// covered, i.e. no active rentor pays for it (every active rentor excludes
  /// it, or there are none).
  static double? shareFor(BillType type, DateTime asOf, List<Rentor> rentors) {
    var covered = false;
    var total = 0.0;
    for (final rentor in rentors) {
      if (!rentor.isActiveOn(asOf)) continue;
      if (rentor.excludedBillTypes.contains(type)) continue;
      covered = true;
      total += rentor.percentageFor(type);
    }
    if (!covered) return null;
    return 100 - total;
  }

  /// The share for every covered [BillType] as of [asOf].
  static Map<BillType, double> sharesAsOf(DateTime asOf, List<Rentor> rentors) {
    final result = <BillType, double>{};
    for (final type in BillType.values) {
      final share = shareFor(type, asOf, rentors);
      if (share != null) result[type] = share;
    }
    return result;
  }

  /// The amount already paid toward [bill].
  ///
  /// [Bill.amountPaid] wins when set (callers update it before the status, so
  /// the status may be stale). Otherwise a `paid` bill counts as fully paid
  /// and anything else as 0.
  static double paidAmount(Bill bill) {
    final amountPaid = bill.amountPaid;
    if (amountPaid != null) return amountPaid;
    return bill.status == PaymentStatus.paid ? bill.amount : 0.0;
  }

  /// Whether [bill] counts as fully paid given the Property Manager share
  /// computed from [rentors] as of the bill's due date.
  ///
  /// The unpaid remainder may exceed the share by a tolerance of
  /// `max($1.00, $0.50 x N)`, where N is the number of rentors active on the
  /// due date that do not exclude the bill's type (see [_tolerancePerRentor]).
  static bool isConsideredPaid(Bill bill, List<Rentor> rentors) {
    final share = shareFor(bill.type, bill.dueDate, rentors);
    if (share == null) return false;
    final unpaid = bill.amount - paidAmount(bill);
    if (unpaid <= 0) return true;
    final threshold = (share / 100).clamp(0.0, 1.0);
    return unpaid <= bill.amount * threshold + _toleranceFor(bill, rentors);
  }

  /// `max(_minTolerance, _tolerancePerRentor x N)` with N the rentors active on
  /// the bill's due date that pay for its type.
  static double _toleranceFor(Bill bill, List<Rentor> rentors) {
    final payers = rentors
        .where((r) =>
            r.isActiveOn(bill.dueDate) &&
            !r.excludedBillTypes.contains(bill.type))
        .length;
    return max(_minTolerance, _tolerancePerRentor * payers);
  }

  /// The status [bill] should have under the current [rentors].
  ///
  /// Returns [Bill.status] unchanged when it is `unknown`, or when the bill's
  /// type is not covered by any active rentor (no share to compare against,
  /// so the existing status is kept rather than re-derived).
  static PaymentStatus recomputeStatus(Bill bill, List<Rentor> rentors) {
    if (bill.status == PaymentStatus.unknown) return bill.status;
    if (shareFor(bill.type, bill.dueDate, rentors) == null) return bill.status;
    if (isConsideredPaid(bill, rentors)) return PaymentStatus.paid;
    if (paidAmount(bill) > 0) return PaymentStatus.partial;
    return PaymentStatus.unpaid;
  }

  /// Whether any field that feeds the share calculation differs between
  /// [before] and [after] (start date, default percentage, per-type
  /// percentages, excluded types). Name/contact changes do not count.
  static bool shareInputsChanged(Rentor before, Rentor after) {
    if (!_sameDay(before.startDate, after.startDate)) return true;
    if (before.defaultPercentage != after.defaultPercentage) return true;
    if (!_sameMap(before.billPercentages, after.billPercentages)) return true;
    return !_sameSet(before.excludedBillTypes, after.excludedBillTypes);
  }

  /// The bills whose status may change when a rentor goes from [before]
  /// (`null` for a new rentor) to [after].
  ///
  /// Excludes `unknown`-status bills, bills due before the earliest affected
  /// start date (no bound if either start date is null), and bills of types
  /// excluded by both [before] and [after].
  static List<Bill> billsAffectedByChange(
    Rentor? before,
    Rentor after,
    List<Bill> bills,
  ) {
    final afterStart = after.startDate;
    final beforeStart = before?.startDate;
    DateTime? earliest;
    if (afterStart == null || (before != null && beforeStart == null)) {
      earliest = null;
    } else if (beforeStart == null) {
      earliest = _dateOnly(afterStart);
    } else {
      final b = _dateOnly(beforeStart);
      final a = _dateOnly(afterStart);
      earliest = a.isBefore(b) ? a : b;
    }

    return bills.where((bill) {
      if (bill.status == PaymentStatus.unknown) return false;
      if (earliest != null && _dateOnly(bill.dueDate).isBefore(earliest)) {
        return false;
      }
      final excludedByAfter = after.excludedBillTypes.contains(bill.type);
      final excludedByBefore =
          before == null || before.excludedBillTypes.contains(bill.type);
      return !(excludedByAfter && excludedByBefore);
    }).toList();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return _dateOnly(a) == _dateOnly(b);
  }

  static bool _sameMap(Map<BillType, double> a, Map<BillType, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static bool _sameSet(List<BillType> a, List<BillType> b) {
    final sa = a.toSet();
    final sb = b.toSet();
    return sa.length == sb.length && sa.containsAll(sb);
  }
}
