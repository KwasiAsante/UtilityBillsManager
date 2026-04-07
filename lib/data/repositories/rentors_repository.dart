import 'package:flutter/foundation.dart';
import '../models/rentor.dart';
import '../models/result.dart';
import '../../helpers/rentors/rentors_helper.dart';

/// Singleton [ChangeNotifier] repository that manages the in-memory list of
/// [Rentor] records and delegates persistence to [RentorsHelper].
///
/// Screens subscribe via `context.watch<RentorsRepository>()`. Any mutating
/// operation (create / update / delete) automatically calls [reload] so the
/// in-memory list stays current before [notifyListeners] fires.
class RentorsRepository extends ChangeNotifier {
  static final RentorsRepository _instance = RentorsRepository._internal();
  factory RentorsRepository() => _instance;
  RentorsRepository._internal();

  final RentorsHelper _helper = RentorsHelper();

  /// The current list of rentors held in memory.
  List<Rentor> rentors = [];

  /// The error message from the most recent failed operation, or `null` if the
  /// last operation succeeded.
  String? lastError;

  /// Fetches all rentors from the database and refreshes [rentors].
  ///
  /// Always calls [notifyListeners] regardless of outcome.
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

  /// Persists a new [rentor] to the database and reloads the list on success.
  Future<Result<Rentor>> create(Rentor rentor) async {
    final result = await _helper.createRentor(rentor);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Updates an existing [rentor] record and reloads the list on success.
  Future<Result<Rentor>> update(Rentor rentor) async {
    final result = await _helper.updateRentor(rentor);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Deletes the rentor identified by [id] and reloads the list on success.
  Future<Result<Rentor>> delete(String id) async {
    final result = await _helper.deleteRentor(id);
    if (result.isSuccess) await reload();
    return result;
  }
}
