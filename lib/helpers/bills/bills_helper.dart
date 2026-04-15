import 'dart:math';

import '../database/database_helper.dart';
import '../rentors/rentors_helper.dart';
import '../../utils/app_logger.dart';
import '../../config/app_config.dart';
import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/models/result.dart';
import '../../services/api/api_service.dart';

/// Singleton service layer for bill-related persistence and status logic.
///
/// Routes every operation to either the local SQLite [DatabaseHelper] (when
/// [AppConfig.mode] == [AppMode.server]) or the remote HTTP [ApiService]
/// (client mode).  Also owns payment-status side-effects: when a [Payment] is created
/// or deleted the helper credits / reverses the applied amount on each linked
/// [Bill] and updates its [PaymentStatus].
class BillsHelper {
  static final BillsHelper _instance = BillsHelper._internal();

  factory BillsHelper() {
    return _instance;
  }

  BillsHelper._internal();

  /// Returns the [DatabaseHelper] singleton. Only use when
  /// [AppConfig.mode] == [AppMode.server].
  DatabaseHelper get dbHelper => DatabaseHelper();

  //region CRUD Operations
  /// Persists [bill] to the local DB or remote API and returns a [Result]
  /// containing the created bill on success.
  Future<Result<Bill>> createBill(Bill bill) async {
    if (AppConfig.mode == AppMode.server) {
      final id = await dbHelper.createBill(bill);
      if (id >= 0) {
        return Result.success(data: bill);
      } else {
        return Result.error(
          errorMessage: "Error when creating Bill ${bill.id}",
        );
      }
    } else {
      final returnValue = await ApiService.bills().createBill(bill);
      if (returnValue == "OK") {
        return Result.success(data: bill);
      } else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Fetches a single bill by [billId].  Returns `Result.success(data: null)`
  /// if no matching bill is found.
  Future<Result<Bill?>> readBill(String billId) async {
    try {
      Bill? bill;
      if (AppConfig.mode == AppMode.server) {
        bill = await dbHelper.readBill(billId);
      } else {
        bill = await ApiService.bills().getBill(billId);
      }
      return Result.success(data: bill);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Returns all bills from the data source.
  Future<Result<List<Bill>>> readAllBills() async {
    try {
      List<Bill> bills;
      if (AppConfig.mode == AppMode.server) {
        bills = await dbHelper.readAllBills();
      } else {
        bills = await ApiService.bills().getAllBills();
      }
      return Result.success(data: bills);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Returns bills filtered by payment status.
  ///
  /// Accepts either a raw [status] string or a [PaymentStatus] enum value (one
  /// must be provided).  Optionally restrict results to a specific set of
  /// [billIds].
  Future<Result<List<Bill>>> readBillsByStatus({
    String? status,
    PaymentStatus? paymentStatus,
    List<String>? billIds,
  }) async {
    try {
      if (status == null && paymentStatus != null) {
        status = paymentStatus.name.toLowerCase();
      } else if (status == null && paymentStatus == null) {
        return Result.error(
          errorMessage: "Either status or paymentStatus must be provided",
        );
      }

      List<Bill> bills =
          (AppConfig.mode == AppMode.server)
              ? await dbHelper.readBillsByStatus(status!, ids: billIds)
              : await ApiService.bills().getBillsByStatus(
                status!,
                ids: billIds,
              );

      return Result.success(data: bills);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Updates [bill] in the data source and returns a [Result] with the updated bill.
  Future<Result<Bill>> updateBill(Bill bill) async {
    if (AppConfig.mode == AppMode.server) {
      final id = await dbHelper.updateBill(bill);
      if (id >= 0) {
        return Result.success(data: bill);
      } else {
        return Result.error(
          errorMessage: "Error when updating Bill ${bill.id}",
        );
      }
    } else {
      final returnValue = await ApiService.bills().updateBill(bill);
      if (returnValue == "OK") {
        return Result.success();
      } else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Deletes the bill identified by [id] from the data source.
  Future<Result<Bill>> deleteBill(String id) async {
    if (AppConfig.mode == AppMode.server) {
      final billsDeleted = await dbHelper.deleteBill(id);
      if (billsDeleted > 0) {
        return Result.success();
      } else {
        return Result.error(errorMessage: "Error when deleting Bill $id");
      }
    } else {
      final returnValue = await ApiService.bills().deleteBill(id);
      if (returnValue == "OK") {
        return Result.success();
      } else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Deletes all bills from the data source.
  Future<Result<void>> deleteAllBills() async {
    if (AppConfig.mode == AppMode.server) {
      await dbHelper.deleteAllBills();
      return Result.success();
    } else {
      final returnValue = await ApiService.bills().deleteAllBills();
      if (returnValue == "OK") {
        return Result.success();
      }
      return Result.error(errorMessage: returnValue);
    }
  }
  //endregion

  /// Credits [payment.amountPaid] toward the provided [bills] (or fetches them
  /// by [billIds]) and updates each bill's [PaymentStatus].
  ///
  /// Workflow:
  /// 1. Resolve missing bills / rentor from the DB if only IDs are provided.
  /// 2. For each bill, subtract any previously recorded `appliedAmount` from
  ///    the running balance to avoid double-counting.
  /// 3. Call [updateLastPaymentStatus] for each bill, which caps the credited
  ///    amount to what the rentor owes (if any) and persists the new status.
  /// 4. Record the exact amount applied per (payment, bill) pair via
  ///    [_markPaymentBillApplied].
  Future<void> updatePaymentStatuses(
      Payment payment, {
        List<Bill>? bills,
        List<String>? billIds,
        Rentor? rentor,
        String? rentorId,
      }) async {
    if (bills == null && billIds == null) {
      return;
    }

    if (bills == null && billIds != null && billIds.isNotEmpty) {
      final readResult = await readBillsByStatus(
        paymentStatus: PaymentStatus.unpaid,
        billIds: billIds,
      );
      if (readResult.isSuccess && readResult.data != null) {
        bills = readResult.data!;
      } else {
        AppLogger().e(
          "Error reading bills for payment status update: ${readResult.errorMessage}",
        );
        return;
      }
    }

    if (rentor == null && rentorId != null) {
      final rentorResult = await RentorsHelper().readRentor(rentorId);
      if (rentorResult.isSuccess && rentorResult.data != null) {
        rentor = rentorResult.data!;
      } else {
        AppLogger().e(
          "Error reading rentor for payment status update: ${rentorResult.errorMessage}",
        );
        return;
      }
    }

    if (bills != null) {
      double remainingAmount = payment.amountPaid;
      for (var bill in bills) {
        if (AppConfig.mode == AppMode.server) {
          final appliedAmount = await dbHelper.getPaymentBillAppliedAmount(
            payment.paymentId!,
            bill.billId,
          );
          if (appliedAmount == null || appliedAmount <= 0) continue;

          remainingAmount -= appliedAmount;
        }
      }

      for (var bill in bills) {
        final previousRemaining = remainingAmount;
        double amount = await updateLastPaymentStatus(
          remainingAmount,
          bill: bill,
          rentor: rentor,
        );
        remainingAmount = amount;

        if (payment.paymentId != null) {
          final appliedAmount = previousRemaining - remainingAmount;
          await _markPaymentBillApplied(
            payment.paymentId!,
            bill.billId,
            appliedAmount,
          );
        }
      }
    } else {
      AppLogger().w("No bills found for payment status update");
      return;
    }
  }

  /// Delegates to [DatabaseHelper.markPaymentBillApplied] when in local-DB mode.
  /// No-op in API mode (server-side is responsible for recording applied amounts).
  Future<void> _markPaymentBillApplied(
      String paymentId,
      String billId,
      double appliedAmount,
      ) async {
    if (AppConfig.mode == AppMode.server) {
      await dbHelper.markPaymentBillApplied(paymentId, billId, appliedAmount);
    }
  }

  /// Returns the maximum unpaid-fraction that still counts as "considered paid"
  /// for a given bill type, or null if no threshold applies.
  double? _unpaidThreshold(BillType type) {
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

  /// Returns `true` when [bill] has been paid enough to be treated as fully
  /// paid, based on the bill-type threshold from [_unpaidThreshold].
  ///
  /// A bill is considered paid when the remaining unpaid amount is within the
  /// threshold percentage (or within \$1.00 of that threshold amount).
  bool _isConsideredPaid(Bill bill) {
    final threshold = _unpaidThreshold(bill.type);
    if (threshold == null) return false;
    final actualUnpaid = bill.amount - _paidAmount(bill);
    if (actualUnpaid <= 0) return true;
    // Within the percentage threshold, OR within $1.00 of the threshold amount.
    final thresholdAmount = bill.amount * threshold;
    return actualUnpaid <= thresholdAmount + 1.0;
  }

  /// Returns the total amount already paid toward [bill] based on its current
  /// [PaymentStatus]: the recorded [Bill.amountPaid] for `paid`/`partial`
  /// bills, or `0.0` for `unpaid`/`unknown`.
  double _paidAmount(Bill bill) {
    if (bill.status == PaymentStatus.paid) {
      return bill.amountPaid ?? bill.amount;
    } else if (bill.status == PaymentStatus.partial) {
      return bill.amountPaid ?? 0.0;
    }
    return 0.0;
  }

  /// Reverses the payment-status side-effects of a deleted [payment] for each
  /// bill in [billIds].
  ///
  /// For every bill, the previously recorded `appliedAmount` is subtracted from
  /// `bill.amountPaid` and the status is recalculated:
  /// - `paid`    → if the remaining owed amount is within the threshold
  /// - `partial` → if some amount has still been paid
  /// - `unpaid`  → if nothing has been paid
  Future<void> reversePaymentStatusForBills(
      Payment payment,
      List<String> billIds,
      ) async {
    if (payment.paymentId == null || billIds.isEmpty) return;

    if (AppConfig.mode != AppMode.server) return;

    for (final billId in billIds) {
      final appliedAmount = await dbHelper.getPaymentBillAppliedAmount(
        payment.paymentId!,
        billId,
      );
      if (appliedAmount == null || appliedAmount <= 0) continue;

      final billResult = await readBill(billId);
      if (!billResult.isSuccess || billResult.data == null) continue;

      final bill = billResult.data!;
      double newAmountPaid = (bill.amountPaid ?? 0.0) - appliedAmount;
      if (newAmountPaid < 0) newAmountPaid = 0.0;
      bill.amountPaid = newAmountPaid;

      final amountOwed = bill.amount - newAmountPaid;
      final amountLeft =
      (bill.amount * (bill.type == BillType.internet ? 0.5 : 0.3));
      if (_isConsideredPaid(bill)) {
        AppLogger().d(
          "Bill ${bill.billId} is now fully paid after reversing payment. New amount paid: $newAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}",
        );
        bill.status = PaymentStatus.paid;
      } else if (newAmountPaid > 0) {
        AppLogger().d(
          "Bill ${bill.billId} is now partially paid after reversing payment. New amount paid: $newAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}",
        );
        bill.status = PaymentStatus.partial;
      } else {
        AppLogger().d(
          "Bill ${bill.billId} is now unpaid after reversing payment. New amount paid: $newAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}",
        );
        bill.status = PaymentStatus.unpaid;
      }

      final result = await updateBill(bill);
      if (result.isError) {
        AppLogger().e(
          "Error reversing payment for bill ${bill.billId}: ${result.errorMessage}",
        );
      } else {
        AppLogger().d(
          "Reversed payment ${payment.paymentId} from bill ${bill.billId}: -$appliedAmount, new status: ${bill.status.name}",
        );
      }
    }
  }

  /// Applies [amountPaid] toward [bill], respects the rentor's owed share when
  /// [rentor] is provided, persists the updated bill, and returns the
  /// **remaining** balance after crediting this bill.
  ///
  /// The "paid" threshold is bill-type aware:
  /// - Internet bills: paid when owed ≤ 50 % of total amount.
  /// - All other types: paid when owed ≤ 30 % of total amount.
  Future<double> updateLastPaymentStatus(
      double amountPaid, {
        Bill? bill,
        Rentor? rentor,
      }) async {
    if (bill == null) {
      AppLogger().w("No bill provided for last payment status update");
      return 0.0;
    }

    final PaymentStatus formerStatus = bill.status;

    final billAmount = bill.amount;
    double billAmountPaid = bill.amountPaid ?? 0.0;
    double amountPaidTowardsBill = amountPaid;
    if (rentor != null) {
      // owedAmount returns 0.0 for excluded bill types (intentional — a rentor
      // should not have payments applied to bills they are excluded from paying).
      final owedAmount = rentor.owedAmount(bill);
      if (owedAmount <= 0) {
        AppLogger().d(
          "Rentor ${rentor.rentorId} has no owed amount for bill ${bill.billId}, skipping payment status update",
        );
        return 0.0;
      }

      amountPaidTowardsBill = min(amountPaidTowardsBill, owedAmount);
    }
    billAmountPaid += amountPaidTowardsBill;
    bill.amountPaid = billAmountPaid;

    final amountOwed = billAmount - billAmountPaid;
    final amountLeft =
    (billAmount * (bill.type == BillType.internet ? 0.5 : 0.3));
    if (_isConsideredPaid(bill)) {
      AppLogger().d(
        "Bill ${bill.billId} is now fully paid. Amount paid: $billAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}",
      );
      bill.status = PaymentStatus.paid;
    } else if (billAmountPaid > 0) {
      AppLogger().d(
        "Bill ${bill.billId} is now partially paid. Amount paid: $billAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}",
      );
      bill.status = PaymentStatus.partial;
    } else {
      AppLogger().d(
        "Bill ${bill.billId} remains unpaid. Amount paid: $billAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}",
      );
      bill.status = PaymentStatus.unpaid;
    }

    final result = await updateBill(bill);
    if (result.isError) {
      AppLogger().e(
        "Error updating bill ${bill.billId} status: ${result.errorMessage}",
      );
    } else {
      AppLogger().d(
        "Successfully updated bill ${bill.billId} status from ${formerStatus.name} to ${bill.status.name}",
      );
    }

    amountPaid -= amountPaidTowardsBill;
    return amountPaid;
  }
}
