import '../bills/bills_helper.dart';
import '../database/database_helper.dart';
import '../../config/app_config.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/models/result.dart';
import '../../services/api/api_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/bills/property_manager_share.dart';

/// Singleton service layer for rentor-related persistence.
///
/// Routes every operation to either the local SQLite [DatabaseHelper] (when
/// [AppConfig.mode] == [AppMode.server]) or the remote HTTP [ApiService].  Also
/// provides [updateRentorPaymentInfo] for keeping a rentor's
/// `lastPaymentDate` field in sync after a payment is recorded.
class RentorsHelper {
  static final RentorsHelper _instance = RentorsHelper._internal();

  factory RentorsHelper() {
    return _instance;
  }

  RentorsHelper._internal();

  /// Returns the [DatabaseHelper] singleton. Only use when
  /// [AppConfig.mode] == [AppMode.server].
  DatabaseHelper get dbHelper => DatabaseHelper();

  /// Re-derives affected bill statuses after a rentor save (server mode only;
  /// in client mode the server performs the re-check).
  ///
  /// Failures are logged and swallowed so they never turn a successful rentor
  /// create/update into an error.
  Future<void> _recheckBills(Rentor? before, Rentor after) async {
    try {
      await BillsHelper().recheckStatusesForRentorChange(before, after);
    } catch (e) {
      AppLogger().e(
        "Error re-checking bill statuses for Rentor ${after.rentorId}: $e",
      );
    }
  }

  //region CRUD Operations
  //region Rentor
  /// Persists [rentor] to the data source.
  Future<Result<Rentor>> createRentor(Rentor rentor) async {
    if (AppConfig.mode == AppMode.server) {
      final id = await dbHelper.createRentor(rentor);
      if (id >= 0) {
        await _recheckBills(null, rentor);
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
    try {
      Rentor? rentor;
      if (AppConfig.mode == AppMode.server) {
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
    try {
      List<Rentor> rentors;
      if (AppConfig.mode == AppMode.server) {
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
    if (AppConfig.mode == AppMode.server) {
      // Read the prior state before the write so the re-check can diff it.
      Rentor? before;
      try {
        before = await dbHelper.readRentor(rentor.rentorId);
      } catch (e) {
        AppLogger().e(
          "Error reading Rentor ${rentor.rentorId} before update: $e",
        );
      }
      final id = await dbHelper.updateRentor(rentor);
      if (id >= 0) {
        if (before == null ||
            PropertyManagerShare.shareInputsChanged(before, rentor)) {
          await _recheckBills(before, rentor);
        }
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
    if (AppConfig.mode == AppMode.server) {
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
  /// The rentor is identified by [rentorId], or by `rentor.rentorId` when only
  /// [rentor] is given; the passed-in object is used for its id only. The
  /// rentor is always re-read from the data source before it is updated,
  /// because callers typically hold a cached copy (e.g. `payment.rentor` from
  /// the payments cache) that can predate a rentor edit, and saving the whole
  /// stale rentor would overwrite that edit (and make the server re-check bill
  /// statuses against the old values).
  ///
  /// Skips the write, logging the reason, if the read fails or finds nothing.
  Future<void> updateRentorPaymentInfo(Payment payment, {Rentor? rentor, String? rentorId}) async {
    final id = rentorId ?? rentor?.rentorId;
    if (id == null) {
      return;
    }

    final readResult = await readRentor(id);
    final fresh = readResult.data;
    if (!readResult.isSuccess || fresh == null) {
      AppLogger().e(
        "Could not read rentor $id to update payment info: "
        "${readResult.errorMessage ?? 'rentor not found'}",
      );
      return;
    }

    fresh.updateLastPaymentDate(payments: [payment]);
    final results = await updateRentor(fresh);
    if (!results.isSuccess) {
      AppLogger().e("Error updating rentor payment info: ${results.errorMessage}");
    }
    else {
      AppLogger().d("Successfully updated rentor payment info for rentor ${fresh.id}");
    }
  }
  //endregion
  //endregion
}
