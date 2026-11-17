import '../../data/models/bill.dart';
import '../../data/models/result.dart';
import '../../helpers/bills/bills_helper.dart';
import '../../utils/bills/bill_recalculation.dart';

/// The result of applying a batch of bill recalculations.
class RecalculationSummary {
  /// The number of bills successfully updated.
  final int updated;

  /// The number of bills that failed to update.
  final int failed;

  /// Error messages from failed updates, one per failure.
  final List<String> errors;

  RecalculationSummary({
    required this.updated,
    required this.failed,
    required this.errors,
  });
}

/// Applies a list of bill recalculations by writing only the changed ones.
///
/// Takes a list of [BillRecalculation] objects, filters to those where
/// [BillRecalculation.changed] is true, and updates each via an injected
/// [updateBill] function (or [BillsHelper().updateBill] if none is provided).
/// Returns a [RecalculationSummary] with counts and error messages.
class BillRecalculationRunner {
  /// Creates a runner that applies recalculations via [updateBill].
  ///
  /// If [updateBill] is null, [apply] resolves [BillsHelper().updateBill]
  /// at call time so tests can avoid constructing [BillsHelper].
  BillRecalculationRunner({
    Future<Result<Bill>> Function(Bill bill)? updateBill,
  }) : _updateBill = updateBill;

  final Future<Result<Bill>> Function(Bill bill)? _updateBill;

  /// Applies each recalculation in [recalculations] that is marked as changed.
  ///
  /// Writes sequentially in list order, skipping any where [BillRecalculation.changed]
  /// is false. Counts successes as [RecalculationSummary.updated] and failures plus
  /// their error messages (or 'Unknown error') in [RecalculationSummary.failed] and
  /// [RecalculationSummary.errors]. Does not stop on a failure.
  Future<RecalculationSummary> apply(
    List<BillRecalculation> recalculations,
  ) async {
    var updated = 0;
    var failed = 0;
    final errors = <String>[];

    final updateBill =
        _updateBill ?? (Bill bill) => BillsHelper().updateBill(bill);

    for (final recalc in recalculations) {
      if (!recalc.changed) {
        continue;
      }

      final updatedBill = recalc.toUpdatedBill();
      final result = await updateBill(updatedBill);

      if (result.isSuccess) {
        updated++;
      } else {
        failed++;
        errors.add(result.errorMessage ?? 'Unknown error');
      }
    }

    return RecalculationSummary(
      updated: updated,
      failed: failed,
      errors: errors,
    );
  }
}
