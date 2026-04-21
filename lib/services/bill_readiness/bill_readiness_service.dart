import '../bill_summary/bill_summary_service.dart';
import '../../data/models/bill.dart';
import '../../data/models/rentor.dart';
import '../../helpers/bill_readiness/bill_notification_tracker_helper.dart';

/// Returned by [BillReadinessService.checkReadiness] when a rentor's bills are
/// all accounted for and a compose message notification should be shown.
class ComposeNotification {
  final Rentor rentor;

  /// The eligible bills to include in the generated message.
  final List<Bill> bills;

  /// `true` → water group; `false` → regular group.
  final bool isWater;

  const ComposeNotification({
    required this.rentor,
    required this.bills,
    required this.isWater,
  });
}

/// Singleton that checks whether all expected bills for a rentor have been
/// received via notification and returns [ComposeNotification]s when they have.
///
/// Inject [BillNotificationTrackerHelper] via [BillReadinessService.forTesting]
/// to avoid SQLite in unit tests.
class BillReadinessService {
  static final BillReadinessService _instance =
      BillReadinessService._internal();

  factory BillReadinessService() => _instance;

  BillReadinessService._internal()
      : _trackerHelper = BillNotificationTrackerHelper();

  /// Test-only constructor — injects a fake [BillNotificationTrackerHelper].
  BillReadinessService.forTesting(BillNotificationTrackerHelper trackerHelper)
      : _trackerHelper = trackerHelper;

  final BillNotificationTrackerHelper _trackerHelper;
  final BillSummaryService _summaryService = BillSummaryService();

  /// Records receipt of [newBill] for all relevant rentors and returns any
  /// compose notifications that should be displayed.
  ///
  /// The caller must:
  /// 1. Persist [newBill] and reload repositories before calling this.
  /// 2. Call [BillNotificationTrackerHelper.logComposeNotificationSent] and
  ///    show each returned notification.
  ///
  /// [now] is injectable for deterministic testing.
  Future<List<ComposeNotification>> checkReadiness(
    Bill newBill,
    List<Rentor> allRentors,
    List<Bill> allBills, {
    DateTime? now,
  }) async {
    final ref = now ?? DateTime.now();
    final results = <ComposeNotification>[];

    final relevantRentors = allRentors.where((r) =>
        r.billPercentages.containsKey(newBill.type) &&
        !r.excludedBillTypes.contains(newBill.type));

    for (final rentor in relevantRentors) {
      // Record receipt once.
      final trackedResult =
          await _trackerHelper.hasBillBeenTracked(rentor.rentorId, newBill.billId);
      final alreadyTracked = trackedResult.isSuccess && (trackedResult.data ?? false);
      if (!alreadyTracked) {
        await _trackerHelper.trackBill(
          rentorId: rentor.rentorId,
          billId: newBill.billId,
          billType: newBill.type.name,
          month: ref.month,
          year: ref.year,
        );
      }

      final trackedRowsResult = await _trackerHelper.getTrackedBills(
        rentorId: rentor.rentorId,
        month: ref.month,
        year: ref.year,
      );
      final trackedIds = (trackedRowsResult.isSuccess
              ? trackedRowsResult.data ?? []
              : <dynamic>[])
          .map((t) => t.billId as String)
          .toSet();

      final eligibleBills =
          _summaryService.getEligibleBills(rentor, allBills, now: ref);
      final regularBills =
          eligibleBills.where((b) => b.type != BillType.water).toList();
      final waterBills =
          eligibleBills.where((b) => b.type == BillType.water).toList();

      // Regular group
      final regularSentResult = await _trackerHelper.hasComposeNotificationBeenSent(
        rentorId: rentor.rentorId,
        month: ref.month,
        year: ref.year,
        billGroup: 'regular',
      );
      final regularSent =
          regularSentResult.isSuccess && (regularSentResult.data ?? false);
      if (!regularSent &&
          _isRegularGroupComplete(rentor, regularBills, trackedIds)) {
        results.add(
            ComposeNotification(rentor: rentor, bills: regularBills, isWater: false));
      }

      // Water group (only if rentor has water configured)
      if (rentor.billPercentages.containsKey(BillType.water)) {
        final waterSentResult = await _trackerHelper.hasComposeNotificationBeenSent(
          rentorId: rentor.rentorId,
          month: ref.month,
          year: ref.year,
          billGroup: 'water',
        );
        final waterSent =
            waterSentResult.isSuccess && (waterSentResult.data ?? false);
        if (!waterSent && _isWaterGroupComplete(waterBills, trackedIds)) {
          results.add(
              ComposeNotification(rentor: rentor, bills: waterBills, isWater: true));
        }
      }
    }

    return results;
  }

  /// Returns `true` when every non-water type in [rentor.billPercentages] has
  /// at least one eligible bill AND every eligible bill of that type is tracked.
  bool _isRegularGroupComplete(
    Rentor rentor,
    List<Bill> regularBills,
    Set<String> trackedIds,
  ) {
    final requiredTypes = rentor.billPercentages.keys
        .where((t) => t != BillType.water)
        .toList();

    if (requiredTypes.isEmpty) return false;

    for (final billType in requiredTypes) {
      final billsOfType =
          regularBills.where((b) => b.type == billType).toList();
      if (billsOfType.isEmpty) return false; // still waiting for this type
      if (billsOfType.any((b) => !trackedIds.contains(b.billId))) return false;
    }
    return true;
  }

  /// Returns `true` when [waterBills] is non-empty and every water bill is
  /// tracked.
  bool _isWaterGroupComplete(
    List<Bill> waterBills,
    Set<String> trackedIds,
  ) {
    if (waterBills.isEmpty) return false;
    return waterBills.every((b) => trackedIds.contains(b.billId));
  }
}
