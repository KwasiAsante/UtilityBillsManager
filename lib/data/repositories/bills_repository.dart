import 'package:flutter/foundation.dart';
import '../models/bill.dart';
import '../models/result.dart';
import '../../helpers/bills/bills_helper.dart';

class BillsRepository extends ChangeNotifier {
  static final BillsRepository _instance = BillsRepository._internal();
  factory BillsRepository() => _instance;
  BillsRepository._internal();

  final BillsHelper _helper = BillsHelper();

  List<Bill> bills = [];
  String? lastError;

  Future<void> reload() async {
    final result = await _helper.readAllBills();
    if (result.isSuccess) {
      bills = result.data!;
      lastError = null;
    } else {
      lastError = result.errorMessage;
    }
    notifyListeners();
  }

  Future<Result<Bill>> create(Bill bill) async {
    final result = await _helper.createBill(bill);
    if (result.isSuccess) await reload();
    return result;
  }

  Future<Result<Bill>> update(Bill bill) async {
    final result = await _helper.updateBill(bill);
    if (result.isSuccess) await reload();
    return result;
  }

  Future<Result<Bill>> delete(String id) async {
    final result = await _helper.deleteBill(id);
    if (result.isSuccess) await reload();
    return result;
  }
}
