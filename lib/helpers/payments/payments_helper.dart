import 'package:utility_bills_manager/helpers/database/database_helper.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/services/api/api_service.dart';
import 'package:utility_bills_manager/data/models/app_state.dart';

import '../../data/models/bill.dart';
import '../../data/models/rentor.dart';
import '../bills/bills_helper.dart';

/// Singleton service layer for payment-related persistence.
///
/// Routes every operation to either the local SQLite [DatabaseHelper] (when
/// `AppState().localDB` is `true`) or the remote HTTP [ApiService] (server
/// mode).  On delete it also delegates to [BillsHelper] to reverse any
/// payment-status side-effects that were applied when the payment was created.
class PaymentsHelper {
  static final PaymentsHelper _instance = PaymentsHelper._internal();

  factory PaymentsHelper() {
    return _instance;
  }

  PaymentsHelper._internal();

  /// Returns the [DatabaseHelper] singleton when in local-DB mode, or `null`
  /// when API mode is active.
  DatabaseHelper? get dbHelper => AppState().localDB ? DatabaseHelper() : null;

  // #region CRUD Operations
  /// Persists [payment] (and its bill links) to the data source.
  Future<Result<Payment>> createPayment(Payment payment) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      final id = await dbHelper.createPayment(payment);
      if (id >= 0) {
        return Result.success(data: payment);
      } else {
        return Result.error(
          errorMessage: "Error when creating Payment ${payment.id}",
        );
      }
    } else {
      final returnValue = await ApiService.payments().createPayment(payment);
      if (returnValue == "OK") {
        return Result.success(data: payment);
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Retrieves a single payment by [id], optionally joining related bills and
  /// rentor via [include] flags.
  Future<Result<Payment?>> readPayment(String id, {Map<String, bool>? include}) async {
    final dbHelper = this.dbHelper;
    try {
      Payment? payment;
      if (dbHelper != null) {
        payment = await dbHelper.readPayment(id, include: include);
      } else {
        payment = await ApiService.payments().getPayment(id, include: include);
      }
      return Result.success(data: payment);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Returns all payments, optionally filtered to [paymentIds] and with
  /// related records eager-loaded via [include] flags.
  Future<Result<List<Payment>>> readAllPayments({Map<String, bool>? include, List<String>? paymentIds}) async {
    final dbHelper = this.dbHelper;
    try {
      List<Payment> payments;
      if (dbHelper != null) {
        payments = await dbHelper.readAllPayments(include: include, ids: paymentIds);
      } else {
        payments = await ApiService.payments().getAllPayments(include: include, ids: paymentIds);
      }
      return Result.success(data: payments);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Updates [payment] in the data source (including incremental bill-link diff).
  Future<Result<Payment>> updatePayment(Payment payment) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      final id = await dbHelper.updatePayment(payment);
      if (id >= 0) {
        return Result.success(data: payment);
      } else {
        return Result.error(
          errorMessage: "Error when updating Payment ${payment.id}",
        );
      }
    } else {
      final returnValue = await ApiService.payments().updatePayment(payment);
      if (returnValue == "OK") {
        return Result.success(data: payment);
      } else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Attaches a bill to [payment] (by resolved [bill] object or [billId]) and
  /// persists the updated payment.
  Future<Result<Payment>> updatePaymentBillReference(Payment payment, {String? billId, Bill? bill}) async {
    final dbHelper = this.dbHelper;
    try {
      if (bill == null && billId == null) {
        return Result.error(errorMessage: "Either billId or bill must be provided");
      }

      if (bill == null && billId != null) {
        bill = (dbHelper != null)
            ? await dbHelper.readBill(billId)
            : await ApiService.bills().getBill(billId);

        if (bill == null) {
          return Result.error(errorMessage: "Bill with ID $billId not found");
        }
      }

      if (bill != null) {
        payment.addBill(bill);
        if (dbHelper != null) {
          int id = await dbHelper.updatePayment(payment);
          if (id >= 0) {
            return Result.success(data: payment);
          } else {
            return Result.error(
              errorMessage: "Error when updating Payment ${payment.id} Bill reference",
            );
          }
        } else {
          final returnValue = await ApiService.payments().updatePayment(payment);
          if (returnValue == "OK") {
            return Result.success();
          } else {
            return Result.error(errorMessage: returnValue);
          }
        }
      } else {
        return Result.error(errorMessage: "Bill is null");
      }
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Attaches a rentor to [payment] (by resolved [rentor] object or [rentorId])
  /// and persists the updated payment.
  Future<Result<Payment>> updatePaymentRentorReference(Payment payment, {String? rentorId, Rentor? rentor}) async {
    final dbHelper = this.dbHelper;
    try {
      if (rentor == null && rentorId == null) {
        return Result.error(errorMessage: "Either rentorId or rentor must be provided");
      }

      if (rentor == null && rentorId != null) {
        rentor = (dbHelper != null)
            ? await dbHelper.readRentor(rentorId)
            : await ApiService.rentors().getRentor(rentorId);

        if (rentor == null) {
          return Result.error(errorMessage: "Rentor with ID $rentorId not found");
        }
      }

      if (rentor != null) {
        payment.addRentor(rentor);
        if (dbHelper != null) {
          int id = await dbHelper.updatePayment(payment);
          if (id >= 0) {
            return Result.success(data: payment);
          } else {
            return Result.error(
              errorMessage: "Error when updating Payment ${payment.id} Rentor reference",
            );
          }
        } else {
          final returnValue = await ApiService.payments().updatePayment(payment);
          if (returnValue == "OK") {
            return Result.success();
          } else {
            return Result.error(errorMessage: returnValue);
          }
        }
      } else {
        return Result.error(errorMessage: "Rentor is null");
      }
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Deletes the payment identified by [id].
  ///
  /// Before deleting, the payment is fetched (with bill data) so that
  /// [BillsHelper.reversePaymentStatusForBills] can undo the bill-status
  /// side-effects that were applied when this payment was first created.
  Future<Result<void>> deletePayment(String id) async {
    final dbHelper = this.dbHelper;

    // Fetch the payment before deleting so we can reverse bill statuses.
    final paymentResult = await readPayment(id, include: {'bill': true});
    final payment = paymentResult.isSuccess ? paymentResult.data : null;

    if (dbHelper != null) {
      final rowsDeleted = await dbHelper.deletePayment(id);
      if (rowsDeleted > 0) {
        if (payment != null && payment.billIds != null && payment.billIds!.isNotEmpty) {
          await BillsHelper().reversePaymentStatusForBills(payment, payment.billIds!);
        }
        return Result.success();
      } else {
        return Result.error(errorMessage: "Error when deleting Payment $id");
      }
    } else {
      final returnValue = await ApiService.payments().deletePayment(id);
      if (returnValue == "OK") {
        if (payment != null && payment.billIds != null && payment.billIds!.isNotEmpty) {
          await BillsHelper().reversePaymentStatusForBills(payment, payment.billIds!);
        }
        return Result.success();
      } else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Deletes all payments and reverses their bill-status side-effects.
  ///
  /// All payments are fetched first so each bill's `amountPaid` and status can
  /// be rolled back.  In API mode falls back to per-payment deletes if the
  /// server does not implement a bulk-delete endpoint.
  Future<Result<void>> deleteAllPayments() async {
    final dbHelper = this.dbHelper;

    // Fetch all payments before deleting so we can reverse bill statuses.
    final allPaymentsResult = await readAllPayments(include: {'bill': true});
    final allPayments = allPaymentsResult.isSuccess ? (allPaymentsResult.data ?? []) : <Payment>[];

    if (dbHelper != null) {
      await dbHelper.deleteAllPayments();
      for (final payment in allPayments) {
        if (payment.billIds != null && payment.billIds!.isNotEmpty) {
          await BillsHelper().reversePaymentStatusForBills(payment, payment.billIds!);
        }
      }
      return Result.success();
    } else {
      try {
        final returnValue = await ApiService.payments().deleteAllPayments();
        if (returnValue == "OK") {
          for (final payment in allPayments) {
            if (payment.billIds != null && payment.billIds!.isNotEmpty) {
              await BillsHelper().reversePaymentStatusForBills(payment, payment.billIds!);
            }
          }
          return Result.success();
        }
        return Result.error(errorMessage: returnValue);
      } on NoSuchMethodError {
        // Backward-compatible fallback for API variants without bulk delete.
        for (final payment in allPayments) {
          if (payment.paymentId != null) {
            await ApiService.payments().deletePayment(payment.paymentId!);
            if (payment.billIds != null && payment.billIds!.isNotEmpty) {
              await BillsHelper().reversePaymentStatusForBills(payment, payment.billIds!);
            }
          }
        }
        return Result.success();
      } catch (e) {
        return Result.error(errorMessage: e.toString());
      }
    }
  }

  // #endregion
}
