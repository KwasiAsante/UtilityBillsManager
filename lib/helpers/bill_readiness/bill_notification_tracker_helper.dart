import '../database/database_helper.dart';
import '../../data/models/bill_notification_tracker.dart';

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

  DatabaseHelper get _db => DatabaseHelper();

  /// Returns `true` if this [billId] has already been recorded for [rentorId].
  Future<bool> hasBillBeenTracked(String rentorId, String billId) =>
      _db.billNotificationTrackerExists(rentorId: rentorId, billId: billId);

  /// Inserts a tracker row for the given (rentor, bill) pair.
  Future<void> trackBill({
    required String rentorId,
    required String billId,
    required String billType,
    required int month,
    required int year,
  }) async {
    await _db.insertBillNotificationTracker(
      BillNotificationTracker(
        rentorId: rentorId,
        billId: billId,
        billType: billType,
        month: month,
        year: year,
        receivedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Returns all tracker rows for [rentorId] in [month]/[year].
  Future<List<BillNotificationTracker>> getTrackedBills({
    required String rentorId,
    required int month,
    required int year,
  }) =>
      _db.getBillNotificationTrackers(
          rentorId: rentorId, month: month, year: year);

  /// Returns `true` if a compose notification has already been sent for the
  /// given [rentorId]/[month]/[year]/[billGroup] combination.
  Future<bool> hasComposeNotificationBeenSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) =>
      _db.hasComposeNotificationLog(
          rentorId: rentorId, month: month, year: year, billGroup: billGroup);

  /// Records that a compose notification was sent for [rentorId]/[month]/[year]/[billGroup].
  Future<void> logComposeNotificationSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async {
    await _db.insertComposeNotificationLog(
        rentorId: rentorId, month: month, year: year, billGroup: billGroup);
  }
}
