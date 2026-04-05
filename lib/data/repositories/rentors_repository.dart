import 'package:flutter/foundation.dart';
import '../models/rentor.dart';
import '../models/result.dart';
import '../../helpers/rentors/rentors_helper.dart';

class RentorsRepository extends ChangeNotifier {
  static final RentorsRepository _instance = RentorsRepository._internal();
  factory RentorsRepository() => _instance;
  RentorsRepository._internal();

  final RentorsHelper _helper = RentorsHelper();

  List<Rentor> rentors = [];
  String? lastError;

  Future<void> reload() async {
    final result = await _helper.readAllRentors();
    if (result.isSuccess) {
      rentors = result.data!;
      lastError = null;
    } else {
      lastError = result.errorMessage;
    }
    notifyListeners();
  }

  Future<Result<Rentor>> create(Rentor rentor) async {
    final result = await _helper.createRentor(rentor);
    if (result.isSuccess) await reload();
    return result;
  }

  Future<Result<Rentor>> update(Rentor rentor) async {
    final result = await _helper.updateRentor(rentor);
    if (result.isSuccess) await reload();
    return result;
  }

  Future<Result<Rentor>> delete(String id) async {
    final result = await _helper.deleteRentor(id);
    if (result.isSuccess) await reload();
    return result;
  }
}
