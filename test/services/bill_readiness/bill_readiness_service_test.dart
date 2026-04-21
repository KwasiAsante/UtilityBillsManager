import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/bill_notification_tracker.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/helpers/bill_readiness/bill_notification_tracker_helper.dart';
import 'package:utility_bills_manager/services/bill_readiness/bill_readiness_service.dart';

// ── Fake helper ─────────────────────────────────────────────────────────────

class FakeTrackerHelper extends BillNotificationTrackerHelper {
  FakeTrackerHelper() : super.internal();

  final Set<String> _tracked = {}; // '$rentorId:$billId'
  final Set<String> _logged = {}; // '$rentorId:$month:$year:$group'

  @override
  Future<Result<bool>> hasBillBeenTracked(String rentorId, String billId) async =>
      Result.success(data: _tracked.contains('$rentorId:$billId'));

  @override
  Future<Result<void>> trackBill({
    required String rentorId,
    required String billId,
    required String billType,
    required int month,
    required int year,
  }) async {
    _tracked.add('$rentorId:$billId');
    return Result.success();
  }

  @override
  Future<Result<List<BillNotificationTracker>>> getTrackedBills({
    required String rentorId,
    required int month,
    required int year,
  }) async {
    final trackers = _tracked
        .where((k) => k.startsWith('$rentorId:'))
        .map((k) => BillNotificationTracker(
              rentorId: rentorId,
              billId: k.split(':')[1],
              billType: 'unknown',
              month: month,
              year: year,
              receivedAt: '',
            ))
        .toList();
    return Result.success(data: trackers);
  }

  @override
  Future<Result<bool>> hasComposeNotificationBeenSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async =>
      Result.success(data: _logged.contains('$rentorId:$month:$year:$billGroup'));

  @override
  Future<Result<void>> logComposeNotificationSent({
    required String rentorId,
    required int month,
    required int year,
    required String billGroup,
  }) async {
    _logged.add('$rentorId:$month:$year:$billGroup');
    return Result.success();
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Bill _bill({
  required String billId,
  required BillType type,
  DateTime? dueDate,
  PaymentStatus status = PaymentStatus.unpaid,
}) =>
    Bill(
      billId: billId,
      company: 'Test Co',
      type: type,
      amount: 100.0,
      dueDate: dueDate ?? DateTime(2026, 4, 15),
      status: status,
      notes: null,
    );

Rentor _rentor({
  required String rentorId,
  required Map<BillType, double> billPercentages,
  List<BillType> excludedBillTypes = const [],
}) =>
    Rentor(
      rentorId: rentorId,
      name: 'Test Rentor',
      defaultPercentage: 30.0,
      billPercentages: billPercentages,
      excludedBillTypes: excludedBillTypes,
    );

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late FakeTrackerHelper fakeHelper;
  late BillReadinessService service;
  // April 2026
  final now = DateTime(2026, 4, 10);

  setUp(() {
    fakeHelper = FakeTrackerHelper();
    service = BillReadinessService.forTesting(fakeHelper);
  });

  group('checkReadiness — rentor filtering', () {
    test('returns empty when rentor does not include incoming bill type', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35},
      );
      final bill = _bill(billId: 'b1', type: BillType.gas);

      final result = await service.checkReadiness(
        bill, [rentor], [bill], now: now,
      );

      expect(result, isEmpty);
    });

    test('returns empty when rentor excludes incoming bill type', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.gas: 35},
        excludedBillTypes: [BillType.gas],
      );
      final bill = _bill(billId: 'b1', type: BillType.gas);

      final result = await service.checkReadiness(
        bill, [rentor], [bill], now: now,
      );

      expect(result, isEmpty);
    });
  });

  group('checkReadiness — tracker insertion', () {
    test('inserts tracker row for relevant rentor', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final incoming = _bill(billId: 'b1', type: BillType.electric);

      await service.checkReadiness(
        incoming, [rentor], [incoming], now: now,
      );

      final tracked = await fakeHelper.hasBillBeenTracked('r1', 'b1');
      expect(tracked.data, isTrue);
    });

    test('does not insert duplicate tracker row', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35},
      );
      final bill = _bill(billId: 'b1', type: BillType.electric);

      // First call — inserts
      await service.checkReadiness(bill, [rentor], [bill], now: now);
      // Second call — should not re-insert (fake tracks via Set, so idempotent)
      await service.checkReadiness(bill, [rentor], [bill], now: now);

      // Only one entry in the set
      final tracked = await fakeHelper.getTrackedBills(
          rentorId: 'r1', month: 4, year: 2026);
      expect(tracked.data!.length, equals(1));
    });
  });

  group('checkReadiness — regular bill completeness', () {
    test('returns empty when a required bill type has no eligible bills yet', () async {
      // rentor needs electric + gas, but only electric has arrived
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final electricBill = _bill(billId: 'b1', type: BillType.electric);

      final result = await service.checkReadiness(
        electricBill, [rentor], [electricBill], now: now,
      );

      expect(result, isEmpty);
    });

    test('returns empty when not all bills of a type are tracked', () async {
      // 3 gas bills; only 1 has been notified — incoming is gas2, but gas3 still pending
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);
      final gas1 = _bill(billId: 'b2', type: BillType.gas);
      final gas2 = _bill(billId: 'b3', type: BillType.gas);
      final gas3 = _bill(billId: 'b4', type: BillType.gas);
      final allBills = [electric, gas1, gas2, gas3];

      // Mark electric and gas1 as tracked
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b2', billType: 'gas', month: 4, year: 2026);

      // Incoming: gas2 (not yet tracked; gas3 also still pending)
      final result = await service.checkReadiness(
        gas2, [rentor], allBills, now: now,
      );

      expect(result, isEmpty);
    });

    test('returns ComposeNotification when all regular types are fully tracked', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);
      final gas1 = _bill(billId: 'b2', type: BillType.gas);
      final gas2 = _bill(billId: 'b3', type: BillType.gas);
      final allBills = [electric, gas1, gas2];

      // Pre-track electric and gas1
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b2', billType: 'gas', month: 4, year: 2026);

      // Incoming: gas2 — completes coverage
      final result = await service.checkReadiness(
        gas2, [rentor], allBills, now: now,
      );

      expect(result.length, equals(1));
      expect(result.first.isWater, isFalse);
      expect(result.first.rentor.rentorId, equals('r1'));
      expect(result.first.bills.map((b) => b.billId),
          containsAll(['b1', 'b2', 'b3']));
    });

    test('does not return duplicate when log row already exists', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);

      // Pre-track bill and log sent
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.logComposeNotificationSent(
          rentorId: 'r1', month: 4, year: 2026, billGroup: 'regular');

      final result = await service.checkReadiness(
        electric, [rentor], [electric], now: now,
      );

      expect(result, isEmpty);
    });
  });

  group('checkReadiness — water bill completeness', () {
    test('returns water ComposeNotification when all water bills tracked', () async {
      // Water bills are eligible when due in the next month (May 2026 when now = April 2026)
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.water: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);
      final water = _bill(
          billId: 'b2',
          type: BillType.water,
          dueDate: DateTime(2026, 5, 1)); // due next month — eligible

      final allBills = [electric, water];

      // Pre-track electric so regular group is not triggered
      // (electric is the only regular type; it's complete)
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.logComposeNotificationSent(
          rentorId: 'r1', month: 4, year: 2026, billGroup: 'regular');

      // Incoming: water bill
      final result = await service.checkReadiness(
        water, [rentor], allBills, now: now,
      );

      expect(result.length, equals(1));
      expect(result.first.isWater, isTrue);
      expect(result.first.bills.map((b) => b.billId), contains('b2'));
    });

    test('does not trigger water notification when rentor has no water in billPercentages', () async {
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35},
      );
      final water = _bill(
          billId: 'b1',
          type: BillType.water,
          dueDate: DateTime(2026, 5, 1));

      final result = await service.checkReadiness(
        water, [rentor], [water], now: now,
      );

      expect(result, isEmpty);
    });

    test('water not triggered when not all water bills tracked', () async {
      // 3 water bills; only 1 pre-tracked; incoming is water2, but water3 still pending
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.water: 35},
      );
      final water1 =
          _bill(billId: 'b1', type: BillType.water, dueDate: DateTime(2026, 5, 1));
      final water2 =
          _bill(billId: 'b2', type: BillType.water, dueDate: DateTime(2026, 5, 1));
      final water3 =
          _bill(billId: 'b3', type: BillType.water, dueDate: DateTime(2026, 5, 1));

      // Pre-track water1 only
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'water', month: 4, year: 2026);

      // Incoming: water2 — water3 still pending, not all tracked
      final result = await service.checkReadiness(
        water2, [rentor], [water1, water2, water3], now: now,
      );

      expect(result, isEmpty);
    });
  });

  group('checkReadiness — multi-rentor', () {
    test('returns notifications for all rentors that become complete', () async {
      final john = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final amy = _rentor(
        rentorId: 'r2',
        billPercentages: {BillType.electric: 35, BillType.gas: 35},
      );
      final electric = _bill(billId: 'b1', type: BillType.electric);
      final gas = _bill(billId: 'b2', type: BillType.gas);

      // John has both tracked; Amy only has electric
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b1', billType: 'electric', month: 4, year: 2026);
      await fakeHelper.trackBill(
          rentorId: 'r1', billId: 'b2', billType: 'gas', month: 4, year: 2026);
      await fakeHelper.trackBill(
          rentorId: 'r2', billId: 'b1', billType: 'electric', month: 4, year: 2026);

      // Incoming: gas (for both rentors, since both have gas in billPercentages)
      final result = await service.checkReadiness(
        gas, [john, amy], [electric, gas], now: now,
      );

      // Both rentors are now complete: John was already complete (b2 was pre-tracked),
      // and Amy just got gas tracked — both should receive notifications.
      expect(result.length, equals(2));
      expect(result.map((n) => n.rentor.rentorId), containsAll(['r1', 'r2']));
    });
  });

  group('checkReadiness — December/January boundary', () {
    test('water due in January is eligible when now is December', () async {
      final decNow = DateTime(2026, 12, 10);
      final rentor = _rentor(
        rentorId: 'r1',
        billPercentages: {BillType.water: 35},
      );
      final janWater = _bill(
          billId: 'b1',
          type: BillType.water,
          dueDate: DateTime(2027, 1, 5)); // next month = Jan 2027

      final result = await service.checkReadiness(
        janWater, [rentor], [janWater], now: decNow,
      );

      expect(result.length, equals(1));
      expect(result.first.isWater, isTrue);
    });
  });
}
