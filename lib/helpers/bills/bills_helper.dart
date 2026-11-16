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
import '../../utils/bills/property_manager_share.dart';

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
  Future<Result<List<Bill>>> readAllBills({List<String>? billIds}) async {
    try {
      List<Bill> bills;
      if (AppConfig.mode == AppMode.server) {
        bills = await dbHelper.readAllBills(ids: billIds);
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

  //region Bill Payment
  //region Bill Payment Status Updates
  /// Credits [payment.amountPaid] toward the provided [bills] (or fetches them
  /// by [billIds]) and updates each bill's [PaymentStatus].
  ///
  /// Workflow:
  /// 1. Resolve missing bills / rentor from the DB if only IDs are provided.
  /// 2. For each bill, subtract any previously recorded `appliedAmount` from
  ///    the running balance to avoid double-counting.
  /// 3. Call [_updateLastPaymentStatus] for each bill, which caps the credited
  ///    amount to what the rentor owes (if any) and persists the new status.
  /// 4. Record the exact amount applied per (payment, bill) pair via
  ///    [_markPaymentBillApplied].
  Future<void> updatePaymentStatusForBills(
    Payment payment, {
    List<Bill>? bills,
    List<String>? billIds,
    Rentor? rentor,
    String? rentorId,
  }) async {
    if ((bills == null || bills.isEmpty) &&
        (billIds == null || billIds.isEmpty)) {
      return;
    }

    if (AppConfig.mode == AppMode.server) {
      if (bills == null || bills.isEmpty) {
        bills = [];
        final readResult = await readAllBills(billIds: billIds);
        if (readResult.isSuccess &&
            readResult.data != null &&
            readResult.data!.isNotEmpty) {
          bills.addAll(
            readResult.data!.where(
              (bill) =>
                  bill.status != PaymentStatus.unknown &&
                  bill.status != PaymentStatus.paid,
            ),
          );
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

      if (bills.isEmpty) {
        AppLogger().w("No bills found for payment status update");
        return;
      }

      final rentors = await _loadRentors();
      double remainingAmount = payment.amountPaid;
      for (var bill in bills) {
        final appliedAmount = await dbHelper.getPaymentBillAppliedAmount(
          payment.paymentId,
          bill.billId,
        );
        if (appliedAmount == null || appliedAmount <= 0) continue;

        remainingAmount -= appliedAmount;
      }

      for (var bill in bills) {
        final previousRemaining = remainingAmount;
        double amount = await _updateLastPaymentStatus(
          remainingAmount,
          bill: bill,
          rentor: rentor,
          rentors: rentors,
        );
        remainingAmount = amount;

        final appliedAmount = previousRemaining - remainingAmount;
        await _markPaymentBillApplied(
          payment.paymentId,
          bill.billId,
          appliedAmount,
        );
      }
    } else {
      if (payment.rentor == null && rentor != null) {
        payment.rentor = rentor;
      }

      if ((payment.rentorId == null || payment.rentorId!.isEmpty) &&
          rentorId != null &&
          rentorId.isNotEmpty) {
        payment.rentorId = rentorId;
      }

      await ApiService.bills().updatePaymentStatusForBills(
        payment,
        bills: bills,
        billIds: billIds,
      );
    }
  }

  /// Reverses the payment-status side-effects of a deleted [payment] for each
  /// bill in [billIds].
  ///
  /// For every bill, the previously recorded `appliedAmount` is subtracted from
  /// `bill.amountPaid` and the status is recalculated:
  /// - `paid`    → if the remaining owed amount is within the Property Manager
  ///   share threshold (see [PropertyManagerShare.isConsideredPaid])
  /// - `partial` → if some amount has still been paid
  /// - `unpaid`  → if nothing has been paid
  Future<void> reversePaymentStatusForBills(
    Payment payment, {
    List<Bill>? bills,
    List<String>? billIds,
  }) async {
    if ((bills == null || bills.isEmpty) &&
        (billIds == null || billIds.isEmpty)) {
      return;
    }

    if (AppConfig.mode == AppMode.server) {
      if (bills == null || bills.isEmpty) {
        final billResult = await readAllBills(billIds: billIds);
        if (!billResult.isSuccess ||
            billResult.data == null ||
            billResult.data!.isEmpty) {
          AppLogger().w(
            "Could not find bills for the provided ids to reverse payment status of payment ${payment.paymentId}",
          );
          return;
        }
        bills = billResult.data;
      }

      final rentors = await _loadRentors();
      for (final bill in bills!) {
        final appliedAmount = await dbHelper.getPaymentBillAppliedAmount(
          payment.paymentId,
          bill.billId,
        );
        if (appliedAmount == null || appliedAmount <= 0) continue;

        double newAmountPaid = (bill.amountPaid ?? 0.0) - appliedAmount;
        if (newAmountPaid < 0) newAmountPaid = 0.0;
        bill.amountPaid = newAmountPaid;

        final amountOwed = bill.amount - newAmountPaid;
        final amountLeft = bill.amount *
            ((PropertyManagerShare.shareFor(bill.type, bill.dueDate, rentors) ??
                    0) /
                100);
        if (_isConsideredPaid(bill, rentors)) {
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
    } else {
      await ApiService.bills().reversePaymentStatusForBills(
        payment,
        bills: bills,
        billIds: billIds,
      );
    }
  }
  //endregion

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

  /// Loads all rentors used to compute the Property Manager share.
  ///
  /// Returns an empty list (and logs an error) if the rentors cannot be read,
  /// in which case no bill type is covered and bills are never considered paid.
  Future<List<Rentor>> _loadRentors() async {
    final result = await RentorsHelper().readAllRentors();
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    AppLogger().e(
      "Error reading rentors for Property Manager share: ${result.errorMessage}",
    );
    return [];
  }

  /// Re-derives the status of bills affected by a rentor create/update.
  ///
  /// [before] is the rentor prior to the change (`null` for a new rentor) and
  /// [after] the saved rentor; call this **after** the rentor write so the new
  /// rentor list is read. Only bills selected by
  /// [PropertyManagerShare.billsAffectedByChange] are considered, and only
  /// [Bill.status] is changed (never [Bill.amountPaid]).
  ///
  /// If the rentor list cannot be loaded (or is empty) nothing is changed.
  /// Returns the number of bills whose status changed.
  Future<int> recheckStatusesForRentorChange(
    Rentor? before,
    Rentor after,
  ) async {
    final rentors = await _loadRentors();
    if (rentors.isEmpty) {
      AppLogger().w(
        "Skipping bill status re-check for rentor ${after.rentorId}: "
        "no rentors loaded",
      );
      return 0;
    }

    final billsResult = await readAllBills();
    if (!billsResult.isSuccess || billsResult.data == null) {
      AppLogger().e(
        "Error reading bills for status re-check: ${billsResult.errorMessage}",
      );
      return 0;
    }

    var changed = 0;
    for (final bill in PropertyManagerShare.billsAffectedByChange(
      before,
      after,
      billsResult.data!,
    )) {
      final newStatus = PropertyManagerShare.recomputeStatus(bill, rentors);
      if (newStatus == bill.status) continue;
      final oldStatus = bill.status;
      bill.status = newStatus;
      final updated = await updateBill(bill);
      if (updated.isSuccess) {
        changed++;
        AppLogger().d(
          "Bill ${bill.billId} status ${oldStatus.name} -> ${newStatus.name} "
          "after rentor ${after.rentorId} change",
        );
      } else {
        bill.status = oldStatus;
        AppLogger().e(
          "Failed to update status of bill ${bill.billId}: "
          "${updated.errorMessage}",
        );
      }
    }
    AppLogger().d(
      "Rentor ${after.rentorId} change re-check updated $changed bill(s)",
    );
    return changed;
  }

  bool _isConsideredPaid(Bill bill, List<Rentor> rentors) =>
      PropertyManagerShare.isConsideredPaid(bill, rentors);

  /// Applies [amountPaid] toward [bill], respects the rentor's owed share when
  /// [rentor] is provided, persists the updated bill, and returns the
  /// **remaining** balance after crediting this bill.
  ///
  /// The "paid" threshold is the Property Manager share computed from
  /// [rentors] as of the bill's due date (see
  /// [PropertyManagerShare.isConsideredPaid]): the bill is paid once the unpaid
  /// remainder is within that share of the total amount (plus a rounding
  /// tolerance of max($1.00, 50 cents per rentor)).
  ///
  /// When [rentor] owes nothing on [bill] (e.g. it is due before their start
  /// date) the bill is left untouched and [amountPaid] is returned unchanged so
  /// the full amount stays available for later bills.
  Future<double> _updateLastPaymentStatus(
    double amountPaid, {
    Bill? bill,
    Rentor? rentor,
    required List<Rentor> rentors,
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
      // owedAmount is 0.0 for excluded bill types and for bills due before the
      // rentor's start date (intentional — a rentor should not have payments
      // applied to bills they do not owe anything on).
      final owedAmount = rentor.owedAmount(bill);
      if (owedAmount <= 0) {
        AppLogger().d(
          "Rentor ${rentor.rentorId} has no owed amount for bill ${bill.billId}, skipping payment status update",
        );
        return amountPaid;
      }

      amountPaidTowardsBill = min(amountPaidTowardsBill, owedAmount);
    }
    billAmountPaid += amountPaidTowardsBill;
    bill.amountPaid = billAmountPaid;

    final amountOwed = billAmount - billAmountPaid;
    final amountLeft = billAmount *
        ((PropertyManagerShare.shareFor(bill.type, bill.dueDate, rentors) ??
                0) /
            100);
    if (_isConsideredPaid(bill, rentors)) {
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

  //endregion
}
