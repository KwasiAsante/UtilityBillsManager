import 'package:utility_bills_manager/helpers/database/database_helper.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/services/api/api_service.dart';
import 'package:utility_bills_manager/data/models/app_state.dart';

class RentorsHelper {
  static final RentorsHelper _instance = RentorsHelper._internal();

  factory RentorsHelper() {
    return _instance;
  }

  RentorsHelper._internal();

  DatabaseHelper? get dbHelper => AppState().localDB ? DatabaseHelper() : null;

  // #region CRUD Operations
  // #region Rentor
  // Create a Rentor
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

  // Retrieve all Rentors
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

  // Update a Rentor
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

  Future<Result<Rentor>> deleteRentor(int id) async {
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
  // #endregion
  // #endregion
}
