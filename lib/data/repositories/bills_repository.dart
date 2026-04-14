import 'package:flutter/foundation.dart';
import '../models/bill.dart';
import '../models/result.dart';
import '../../helpers/bills/bills_helper.dart';
import 'email_data_repository.dart';

/// In-memory cache and [ChangeNotifier] for [Bill] data.
///
/// Screens subscribe to this repository via [addListener] and re-render
/// whenever [reload] is called.  All write operations ([create], [update],
/// [delete]) automatically call [reload] on success so the in-memory list
/// stays consistent with the underlying data source.
///
/// Obtain the singleton via the factory: `BillsRepository()`.
class BillsRepository extends ChangeNotifier {
  static final BillsRepository _instance = BillsRepository._internal();
  factory BillsRepository() => _instance;
  BillsRepository._internal();

  final BillsHelper _helper = BillsHelper();

  List<Bill> bills = [];
  String? lastError;

  /// Fetches all bills from the data source (local DB or API) and stores them
  /// in [bills].  Notifies listeners when done.  If the fetch fails, [lastError]
  /// is set to the error message.
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

  /// Persists a new [bill] and refreshes the in-memory list on success.
  Future<Result<Bill>> create(Bill bill) async {
    final result = await _helper.createBill(bill);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Saves changes to an existing [bill] and refreshes the in-memory list.
  Future<Result<Bill>> update(Bill bill) async {
    final result = await _helper.updateBill(bill);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Deletes the bill with [id] (its `billId` UUID) and refreshes the list.
  Future<Result<Bill>> delete(String id) async {
    final result = await _helper.deleteBill(id);
    if (result.isSuccess) {
      await reload();
      await EmailDataRepository().reload();
    }
    return result;
  }

  /// Deletes all bills from the data source and clears the in-memory list.
  Future<Result<void>> deleteAll() async {
    final result = await _helper.deleteAllBills();
    if (result.isSuccess) {
      await reload();
      await EmailDataRepository().reload();
    }
    return result;
  }
}
