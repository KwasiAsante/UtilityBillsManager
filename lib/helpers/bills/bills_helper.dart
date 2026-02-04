import 'package:utility_bills_manager/helpers/database/database_helper.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/services/api/api_service.dart';
import 'package:utility_bills_manager/data/models/app_state.dart';

class BillsHelper {
  static final BillsHelper _instance = BillsHelper._internal();

  factory BillsHelper() {
    return _instance;
  }

  BillsHelper._internal();

  DatabaseHelper? dbHelper = AppState().localDB ? DatabaseHelper() : null;

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
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
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
  Future<Result<List<Bill>>> readBillsByStatus(String status) async {
    final dbHelper = this.dbHelper;
    try {
      List<Bill> bills;
      if (dbHelper != null) {
        bills = await dbHelper.readBillsByStatus(status);
      } else {
        bills = await ApiService.bills().getBillsByStatus(status);
        bills = List.empty();
      }
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
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  // Delete a Bill
  Future<Result<Bill>> deleteBill(int id) async {
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
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  // #endregion
  // #endregion
}
