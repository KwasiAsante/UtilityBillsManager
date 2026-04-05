import 'package:flutter/foundation.dart';
import '../models/payment.dart';
import '../models/result.dart';
import '../../helpers/payments/payments_helper.dart';

class PaymentsRepository extends ChangeNotifier {
  static final PaymentsRepository _instance = PaymentsRepository._internal();
  factory PaymentsRepository() => _instance;
  PaymentsRepository._internal();

  final PaymentsHelper _helper = PaymentsHelper();

  List<Payment> payments = [];
  String? lastError;

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

  Future<Result<Payment>> create(Payment payment) async {
    final result = await _helper.createPayment(payment);
    if (result.isSuccess) await reload();
    return result;
  }

  Future<Result<Payment>> update(Payment payment) async {
    final result = await _helper.updatePayment(payment);
    if (result.isSuccess) await reload();
    return result;
  }

  Future<Result<void>> delete(String id) async {
    final result = await _helper.deletePayment(id);
    if (result.isSuccess) await reload();
    return result;
  }
}
