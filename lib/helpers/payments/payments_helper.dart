import 'package:utility_bills_manager/helpers/database/database_helper.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/services/api/api_service.dart';
import 'package:utility_bills_manager/data/models/app_state.dart';

class PaymentsHelper {
  static final PaymentsHelper _instance = PaymentsHelper._internal();

  factory PaymentsHelper() {
    return _instance;
  }

  PaymentsHelper._internal();

  DatabaseHelper? get dbHelper => AppState().localDB ? DatabaseHelper() : null;

  // #region CRUD Operations
  // Create a Payment
  Future<Result<Payment>> createPayment(Payment payment) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      final id = await dbHelper.createPayment(payment);
      if (id >= 0) {
        return Result.success();
      } else {
        return Result.error(
          errorMessage: "Error when creating Payment ${payment.id}",
        );
      }
    } else {
      final returnValue = await ApiService.payments().createPayment(payment);
      if (returnValue == "OK") {
        return Result.success();
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  // Retrieve all Payments
  Future<Result<List<Payment>>> readAllPayments() async {
    final dbHelper = this.dbHelper;
    try {
      List<Payment> payments;
      if (dbHelper != null) {
        payments = await dbHelper.readAllPayments();
      } else {
        payments = await ApiService.payments().getAllPayments();
      }
      return Result.success(data: payments);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Delete all Payments
  Future<Result<void>> deleteAllPayments() async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      await dbHelper.deleteAllPayments();
      return Result.success();
    } else {
      try {
        final paymentsApi = ApiService.payments();
        final returnValue = await (paymentsApi as dynamic).deleteAllPayments()
            as String;
        if (returnValue == "OK") {
          return Result.success();
        }
        return Result.error(errorMessage: returnValue);
      } on NoSuchMethodError {
        // Backward-compatible fallback for API variants without bulk delete.
        final payments = await ApiService.payments().getAllPayments();
        for (final payment in payments) {
          if (payment.id != null) {
            await ApiService.payments().deletePayment(payment.id!);
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
