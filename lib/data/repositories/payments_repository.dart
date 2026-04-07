import 'package:flutter/foundation.dart';
import '../models/payment.dart';
import '../models/result.dart';
import '../../helpers/payments/payments_helper.dart';

/// Singleton [ChangeNotifier] repository that manages the in-memory list of
/// [Payment] records and delegates persistence to [PaymentsHelper].
///
/// Screens subscribe via `context.watch<PaymentsRepository>()`. Any mutating
/// operation (create / update / delete) automatically calls [reload] so the
/// in-memory list is always up to date before [notifyListeners] fires.
class PaymentsRepository extends ChangeNotifier {
  static final PaymentsRepository _instance = PaymentsRepository._internal();
  factory PaymentsRepository() => _instance;
  PaymentsRepository._internal();

  final PaymentsHelper _helper = PaymentsHelper();

  /// The current list of payments held in memory.
  List<Payment> payments = [];

  /// The error message from the most recent failed operation, or `null` if the
  /// last operation succeeded.
  String? lastError;

  /// Fetches all payments from the database (with their linked bills and
  /// rentors) and refreshes [payments].
  ///
  /// Always calls [notifyListeners] regardless of success or failure so that
  /// the UI can react to both states.
  Future<void> reload() async {
    final result = await _helper.readAllPayments(include: {'bill': true, 'rentor': true});
    if (result.isSuccess) {
      payments = result.data!;
      lastError = null;
    } else {
      lastError = result.errorMessage;
    }
    notifyListeners();
  }

  /// Persists a new [payment] to the database and reloads the list on success.
  Future<Result<Payment>> create(Payment payment) async {
    final result = await _helper.createPayment(payment);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Updates an existing [payment] record and reloads the list on success.
  Future<Result<Payment>> update(Payment payment) async {
    final result = await _helper.updatePayment(payment);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Deletes the payment identified by [id] and reloads the list on success.
  Future<Result<void>> delete(String id) async {
    final result = await _helper.deletePayment(id);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Deletes all payments from the data source and clears the in-memory list.
  Future<Result<void>> deleteAll() async {
    final result = await _helper.deleteAllPayments();
    if (result.isSuccess) await reload();
    return result;
  }
}
