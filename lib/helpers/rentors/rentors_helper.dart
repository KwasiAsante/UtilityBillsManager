import '../database/database_helper.dart';
import '../../data/models/app_state.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/models/result.dart';
import '../../services/api/api_service.dart';
import '../../utils/app_logger.dart';

/// Singleton service layer for rentor-related persistence.
///
/// Routes every operation to either the local SQLite [DatabaseHelper] (when
/// `AppState().localDB` is `true`) or the remote HTTP [ApiService].  Also
/// provides [updateRentorPaymentInfo] for keeping a rentor's
/// `lastPaymentDate` field in sync after a payment is recorded.
class RentorsHelper {
  static final RentorsHelper _instance = RentorsHelper._internal();

  factory RentorsHelper() {
    return _instance;
  }

  RentorsHelper._internal();

  /// Returns the [DatabaseHelper] singleton when in local-DB mode, or `null`
  /// when API mode is active.
  DatabaseHelper? get dbHelper => AppState().localDB ? DatabaseHelper() : null;

  // #region CRUD Operations
  // #region Rentor
  /// Persists [rentor] to the data source.
  Future<Result<Rentor>> createRentor(Rentor rentor) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      final id = await dbHelper.createRentor(rentor);
      if (id >= 0) {
        return Result.success();
      } else {
        return Result.error(
          errorMessage: "Error when creating Rentor ${rentor.id}",
        );
      }
    } else {
      final returnValue = await ApiService.rentors().createRentor(rentor);
      if (returnValue == "OK") {
        return Result.success();
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Fetches a single rentor by [rentorId].
  Future<Result<Rentor?>> readRentor(String rentorId) async {
    final dbHelper = this.dbHelper;
    try {
      Rentor? rentor;
      if (dbHelper != null) {
        rentor = await dbHelper.readRentor(rentorId);
      } else {
        rentor = await ApiService.rentors().getRentor(rentorId);
      }
      return Result.success(data: rentor);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Returns all rentors from the data source.
  Future<Result<List<Rentor>>> readAllRentors() async {
    final dbHelper = this.dbHelper;
    try {
      List<Rentor> rentors;
      if (dbHelper != null) {
        rentors = await dbHelper.readAllRentors();
      } else {
        rentors = await ApiService.rentors().getAllRentors();
      }
      return Result.success(data: rentors);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Updates [rentor] in the data source.
  Future<Result<Rentor>> updateRentor(Rentor rentor) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      final id = await dbHelper.updateRentor(rentor);
      if (id >= 0) {
        return Result.success();
      } else {
        return Result.error(
          errorMessage: "Error when updating Rentor ${rentor.id}",
        );
      }
    } else {
      final returnValue = await ApiService.rentors().updateRentor(rentor);
      if (returnValue == "OK") {
        return Result.success();
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Deletes the rentor identified by [id] from the data source.
  Future<Result<Rentor>> deleteRentor(String id) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      final deletedRentors = await dbHelper.deleteRentor(id);
      if (deletedRentors > 0) {
        return Result.success();
      } else {
        return Result.error(
          errorMessage: "Error when deleting Rentor $id",
        );
      }
    } else {
      final returnValue = await ApiService.rentors().deleteRentor(id);
      if (returnValue == "OK") {
        return Result.success();
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  /// Refreshes the rentor's `lastPaymentDate` after [payment] is recorded.
  ///
  /// Resolves the rentor from [rentorId] if [rentor] is not provided directly,
  /// then calls [Rentor.updateLastPaymentDate] and persists the change.
  Future<void> updateRentorPaymentInfo(Payment payment, {Rentor? rentor, String? rentorId}) async {
    if (rentor == null && rentorId == null) {
      return;
    }

    if (rentor == null) {
      final readResult = await readRentor(rentorId!);
      if (readResult.isSuccess) {
        rentor = readResult.data!;
      } else {
        return;
      }
    }

    rentor.updateLastPaymentDate(payments: [payment]);
    final results = await updateRentor(rentor);
    if (!results.isSuccess) {
      AppLogger().e("Error updating rentor payment info: ${results.errorMessage}");
    }
    else {
      AppLogger().d("Successfully updated rentor payment info for rentor ${rentor.id}");
    }
  }
  // #endregion
  // #endregion
}
