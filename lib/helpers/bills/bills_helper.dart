import 'package:flutter/foundation.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/helpers/database/database_helper.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/services/api/api_service.dart';
import 'package:utility_bills_manager/data/models/app_state.dart';

import '../../data/models/rentor.dart';
import '../rentors/rentors_helper.dart';

class BillsHelper {
  static final BillsHelper _instance = BillsHelper._internal();

  factory BillsHelper() {
    return _instance;
  }

  BillsHelper._internal();

  DatabaseHelper? get dbHelper => AppState().localDB ? DatabaseHelper() : null;

  // #region CRUD Operations
  // #region Bill
  // Create a Bill
  Future<Result<Bill>> createBill(Bill bill) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
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

  // Retrieve Bills by ID
  Future<Result<Bill?>> readBill(String billId) async {
    final dbHelper = this.dbHelper;
    try {
      Bill? bill;
      if (dbHelper != null) {
        bill = await dbHelper.readBill(billId);
      } else {
        bill = await ApiService.bills().getBill(billId);
      }
      return Result.success(data: bill);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Retrieve all Bills
  Future<Result<List<Bill>>> readAllBills() async {
    final dbHelper = this.dbHelper;
    try {
      List<Bill> bills;
      if (dbHelper != null) {
        bills = await dbHelper.readAllBills();
      } else {
        bills = await ApiService.bills().getAllBills();
      }
      return Result.success(data: bills);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Retrieve all Bills
  Future<Result<List<Bill>>> readBillsByStatus({String? status, PaymentStatus? paymentStatus, List<String>? billIds}) async {
    final dbHelper = this.dbHelper;
    try {
      if (status == null && paymentStatus != null) {
        status = paymentStatus.name.toLowerCase();
      } else if (status == null && paymentStatus == null) {
        return Result.error(errorMessage: "Either status or paymentStatus must be provided");
      }

      List<Bill> bills = (dbHelper != null)
          ? await dbHelper.readBillsByStatus(status!, ids: billIds)
          : await ApiService.bills().getBillsByStatus(status!, ids: billIds);

      return Result.success(data: bills);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Update a Bill
  Future<Result<Bill>> updateBill(Bill bill) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
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

  // Delete a Bill
  Future<Result<Bill>> deleteBill(String id) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
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

  // Delete all Bills
  Future<Result<void>> deleteAllBills() async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
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

  Future<void> updatePaymentStatuses(Payment payment, {List<Bill>? bills, List<String>? billIds, Rentor? rentor, String? rentorId}) async {
    if (bills == null && billIds == null) {
      return;
    }

    if (bills == null && billIds != null && billIds.isNotEmpty) {
      final readResult = await readBillsByStatus(paymentStatus: PaymentStatus.unpaid, billIds: billIds);
      if (readResult.isSuccess && readResult.data != null) {
        bills = readResult.data!;
      } else {
        if (kDebugMode) {
          print("Error reading bills for payment status update: ${readResult.errorMessage}");
        }
        return;
      }
    }

    if (rentor == null && rentorId != null) {
      final rentorResult = await RentorsHelper().readRentor(rentorId);
      if (rentorResult.isSuccess && rentorResult.data != null) {
        rentor = rentorResult.data!;
      } else {
        if (kDebugMode) {
          print("Error reading rentor for payment status update: ${rentorResult.errorMessage}");
        }
        return;
      }
    }

    if (bills != null) {
      double remainingAmount = payment.amountPaid;
      for (var bill in bills) {
        final dbHelper = this.dbHelper;
        if (dbHelper != null) {
          final appliedAmount = await dbHelper.getPaymentBillAppliedAmount(payment.paymentId!, bill.billId);
          if (appliedAmount == null || appliedAmount <= 0) continue;

          remainingAmount -= appliedAmount;
        }
      }

      for (var bill in bills) {
        final previousRemaining = remainingAmount;
        double amount = await updateLastPaymentStatus(remainingAmount, bill: bill, rentor: rentor);
        remainingAmount = amount;

        if (payment.paymentId != null) {
          final appliedAmount = previousRemaining - remainingAmount;
          await _markPaymentBillApplied(payment.paymentId!, bill.billId, appliedAmount);
        }
      }
    }
    else {
      if (kDebugMode) {
        print("No bills found for payment status update");
      }
      return;
    }
  }

  Future<void> _markPaymentBillApplied(String paymentId, String billId, double appliedAmount) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      await dbHelper.markPaymentBillApplied(paymentId, billId, appliedAmount);
    }
  }

  Future<void> reversePaymentStatusForBills(Payment payment, List<String> billIds) async {
    if (payment.paymentId == null || billIds.isEmpty) return;

    final dbHelper = this.dbHelper;
    if (dbHelper == null) return;

    for (final billId in billIds) {
      final appliedAmount = await dbHelper.getPaymentBillAppliedAmount(payment.paymentId!, billId);
      if (appliedAmount == null || appliedAmount <= 0) continue;

      final billResult = await readBill(billId);
      if (!billResult.isSuccess || billResult.data == null) continue;

      final bill = billResult.data!;
      double newAmountPaid = (bill.amountPaid ?? 0.0) - appliedAmount;
      if (newAmountPaid < 0) newAmountPaid = 0.0;
      bill.amountPaid = newAmountPaid;

      final amountOwed = bill.amount - newAmountPaid;
      final amountLeft =  (bill.amount * (bill.type == BillType.internet ? 0.5 : 0.3));
      if (amountOwed <= 0 || amountOwed.toInt() <= amountLeft.toInt()) {
        if (kDebugMode) {
          print("Bill ${bill.billId} is now fully paid after reversing payment. New amount paid: $newAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}");
        }
        bill.status = PaymentStatus.paid;
      } else if (newAmountPaid > 0) {
        if (kDebugMode) {
          print("Bill ${bill.billId} is now partially paid after reversing payment. New amount paid: $newAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}");
        }
        bill.status = PaymentStatus.partial;
      } else {
        if (kDebugMode) {
          print("Bill ${bill.billId} is now unpaid after reversing payment. New amount paid: $newAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}");
        }
        bill.status = PaymentStatus.unpaid;
      }

      final result = await updateBill(bill);
      if (kDebugMode) {
        if (result.isError) {
          print("Error reversing payment for bill ${bill.billId}: ${result.errorMessage}");
        } else {
          print("Reversed payment ${payment.paymentId} from bill ${bill.billId}: -$appliedAmount, new status: ${bill.status.name}");
        }
      }
    }
  }

  Future<double> updateLastPaymentStatus(double amountPaid, {Bill? bill, Rentor? rentor}) async {
    if (bill == null) {
      if (kDebugMode) {
        print("No bill provided for last payment status update");
      }
      return 0.0;
    }

    final PaymentStatus formerStatus = bill.status;

    final billAmount = bill.amount;
    double billAmountPaid = bill.amountPaid ?? 0.0;
    double amountPaidTowardsBill = amountPaid;
    if (rentor != null) {
      final owedAmount = rentor.owedAmount(bill);
      if (owedAmount <= 0) {
        if (kDebugMode) {
          print("Rentor ${rentor.rentorId} has no owed amount for bill ${bill.billId}, skipping payment status update");
        }
        return 0.0;
      }

      // if (amountPaidTowardsBill > owedAmount) {
        amountPaidTowardsBill = owedAmount;
      // }
    }
    billAmountPaid += amountPaidTowardsBill;
    bill.amountPaid = billAmountPaid;

    final amountOwed = billAmount - billAmountPaid;
    final amountLeft =  (billAmount * (bill.type == BillType.internet ? 0.5 : 0.3));
    if (amountOwed <= 0 || amountOwed.toInt() <= amountLeft.toInt()) {
      if (kDebugMode) {
        print("Bill ${bill.billId} is now fully paid. Amount paid: $billAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}");
      }
      bill.status = PaymentStatus.paid;
    } else if (billAmountPaid > 0) {
      if (kDebugMode) {
        print("Bill ${bill.billId} is now partially paid. Amount paid: $billAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}");
      }
      bill.status = PaymentStatus.partial;
    } else {
      if (kDebugMode) {
        print("Bill ${bill.billId} remains unpaid. Amount paid: $billAmountPaid, amount owed: ${amountOwed.toInt()}, amount left: ${amountLeft.toInt()}");
      }
      bill.status = PaymentStatus.unpaid;
    }

    final result = await updateBill(bill);
    if (result.isError) {
      if (kDebugMode) {
        print("Error updating bill ${bill.billId} status: ${result.errorMessage}");
      }
    }
    else {
      if (kDebugMode) {
        print("Successfully updated bill ${bill.billId} status from ${formerStatus.name} to ${bill.status.name}");
      }
    }

    amountPaid -= amountPaidTowardsBill;
    return amountPaid;
  }
  // #endregion
  // #endregion
}
