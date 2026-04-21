import '../database/database_helper.dart';
import '../../data/models/bill_notification_tracker.dart';
import '../../data/models/result.dart';

/// Singleton service layer for bill notification tracking persistence.
///
/// Wraps the two [DatabaseHelper] CRUD regions for
/// `bill_notification_tracker` and `bill_compose_notification_log`.
///
/// Declare a subclass in tests to inject fake behaviour without hitting SQLite:
///
/// ```dart
/// class FakeTrackerHelper extends BillNotificationTrackerHelper {
///   FakeTrackerHelper() : super.internal();
///   // override methods as needed
/// }
/// ```
class BillNotificationTrackerHelper {
  static final BillNotificationTrackerHelper _instance =
      BillNotificationTrackerHelper._internal();

  factory BillNotificationTrackerHelper() => _instance;

  BillNotificationTrackerHelper._internal();

  /// Exposed for subclassing in tests only.
  BillNotificationTrackerHelper.internal();

  DatabaseHelper get dbHelper => DatabaseHelper();

  /// Returns `true` if this [billId] has already been recorded for [rentorId].
  Future<Result<bool>> hasBillBeenTracked(String rentorId, String billId) async {
    try {
      final exists = await dbHelper.billNotificationTrackerExists(
          rentorId: rentorId, billId: billId);
      return Result.success(data: exists);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Inserts a tracker row for the given (rentor, bill) pair.
  Future<Result<void>> trackBill({
    required String rentorId,
    required String billId,
    required String billType,
    required int month,
    required int year,
  }) async {
    try {
      await dbHelper.insertBillNotificationTracker(
        BillNotificationTracker(
          rentorId: rentorId,
          billId: billId,
          billType: billType,
          month: month,
          year: year,
          receivedAt: DateTime.now().toIso8601String(),
        ),
      );
      return Result.success();
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Returns all tracker rows for [rentorId] in [month]/[year].
  Future<Result<List<BillNotificationTracker>>> getTrackedBills({
    required String rentorId,
    required int month,
    required int year,
  }) async {
    try {
      final trackers = await dbHelper.getBillNotificationTrackers(
          rentorId: rentorId, month: month, year: year);
      return Result.success(data: trackers);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Returns `true` if a compose notification has already been sent for the
  /// given [rentorId]/[month]/[year]/[billGroup] combination.
  Future<Result<bool>> hasComposeNotificationBeenSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async {
    try {
      final sent = await dbHelper.hasComposeNotificationLog(
          rentorId: rentorId, month: month, year: year, billGroup: billGroup);
      return Result.success(data: sent);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Records that a compose notification was sent for [rentorId]/[month]/[year]/[billGroup].
  Future<Result<void>> logComposeNotificationSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async {
    try {
      await dbHelper.insertComposeNotificationLog(
          rentorId: rentorId, month: month, year: year, billGroup: billGroup);
      return Result.success();
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }
}
