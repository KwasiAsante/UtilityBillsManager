import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';

void main() {
  Bill makeBill({
    required BillType type,
    required double amount,
    required DateTime dueDate,
  }) =>
      Bill(
        company: 'Test Co',
        type: type,
        amount: amount,
        dueDate: dueDate,
        status: PaymentStatus.unpaid,
        notes: null,
      );

  Rentor makeRentor({
    double defaultPercentage = 15.0,
    Map<BillType, double> billPercentages = const {},
    List<BillType> excluded = const [],
    DateTime? startDate,
  }) =>
      Rentor(
        name: 'Alex Johnson',
        defaultPercentage: defaultPercentage,
        billPercentages: billPercentages,
        excludedBillTypes: excluded,
        startDate: startDate,
      );

  group('isActiveOn', () {
    test('null startDate is always active', () {
      final r = makeRentor();
      expect(r.isActiveOn(DateTime(1990, 1, 1)), isTrue);
      expect(r.isActiveOn(DateTime(2100, 12, 31)), isTrue);
    });

    test('same calendar day counts regardless of time', () {
      final r = makeRentor(startDate: DateTime(2026, 11, 20));
      expect(r.isActiveOn(DateTime(2026, 11, 20, 18)), isTrue);
      expect(r.isActiveOn(DateTime(2026, 11, 19, 23, 59)), isFalse);
    });

    test('startDate time-of-day is ignored', () {
      final r = makeRentor(startDate: DateTime(2026, 11, 20, 22, 30));
      expect(r.isActiveOn(DateTime(2026, 11, 20, 1)), isTrue);
    });
  });

  group('percentageFor', () {
    test('excluded -> 0, override -> override, else default', () {
      final r = makeRentor(
        defaultPercentage: 15,
        billPercentages: {BillType.gas: 30},
        excluded: [BillType.internet],
      );
      expect(r.percentageFor(BillType.internet), 0);
      expect(r.percentageFor(BillType.gas), 30);
      expect(r.percentageFor(BillType.electric), 15);
    });

    test('exclusion wins over an override', () {
      final r = makeRentor(
        billPercentages: {BillType.gas: 30},
        excluded: [BillType.gas],
      );
      expect(r.percentageFor(BillType.gas), 0);
    });
  });

  group('serialization', () {
    test('fromJson/toJson round-trip startDate as yyyy-MM-dd; null stays null',
        () {
      final json = makeRentor(startDate: DateTime(2026, 11, 13)).toJson();
      expect(json['startDate'], '2026-11-13');
      final parsed = Rentor.fromJson(json);
      expect(parsed.startDate, DateTime(2026, 11, 13));

      final nullJson = makeRentor().toJson();
      expect(nullJson.containsKey('startDate'), isTrue);
      expect(nullJson['startDate'], isNull);
      expect(Rentor.fromJson(nullJson).startDate, isNull);
    });

    test('toJson always includes the startDate key (null = always active)', () {
      expect(makeRentor().toJson().containsKey('startDate'), isTrue);
    });

    test('rentorFromJson reads r_startDate', () {
      final r = Rentor.rentorFromJson({
        'r_id': 1,
        'r_rentorId': 'abc',
        'r_name': 'Alex',
        'r_defaultPercentage': 15,
        'r_startDate': '2026-11-13',
      });
      expect(r.startDate, DateTime(2026, 11, 13));

      final none = Rentor.rentorFromJson({
        'r_id': 1,
        'r_rentorId': 'abc',
        'r_name': 'Alex',
        'r_defaultPercentage': 15,
      });
      expect(none.startDate, isNull);
    });

    test('toDbJson includes startDate', () {
      final db = makeRentor(startDate: DateTime(2026, 11, 13)).toDbJson();
      expect(db['startDate'], '2026-11-13');
      expect(makeRentor().toDbJson().containsKey('startDate'), isTrue);
    });
  });

  group('calculateOwedAmount', () {
    test('bill due before startDate -> 0', () {
      final r = makeRentor(startDate: DateTime(2026, 11, 13));
      final bill = makeBill(
        type: BillType.electric,
        amount: 100,
        dueDate: DateTime(2026, 11, 12),
      );
      expect(Rentor.calculateOwedAmount(r, bill), 0.0);
      expect(r.owedAmount(bill), 0.0);
    });

    test('on/after startDate -> 15.0', () {
      final r = makeRentor(startDate: DateTime(2026, 11, 13));
      final onStart = makeBill(
        type: BillType.electric,
        amount: 100,
        dueDate: DateTime(2026, 11, 13),
      );
      final after = makeBill(
        type: BillType.electric,
        amount: 100,
        dueDate: DateTime(2026, 11, 20),
      );
      expect(Rentor.calculateOwedAmount(r, onStart), 15.0);
      expect(Rentor.calculateOwedAmount(r, after), 15.0);
    });

    test('roundToWholeDollar still rounds', () {
      final r = makeRentor(defaultPercentage: 33);
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.5,
        dueDate: DateTime(2026, 11, 20),
      );
      expect(Rentor.calculateOwedAmount(r, bill, roundToWholeDollar: true), 33.0);
    });
  });

  group('calculateOwedBreakdown', () {
    test('skips bills due before startDate', () {
      final r = makeRentor(startDate: DateTime(2026, 11, 13));
      final early = makeBill(
        type: BillType.electric,
        amount: 100,
        dueDate: DateTime(2026, 11, 12),
      );
      final late = makeBill(
        type: BillType.electric,
        amount: 100,
        dueDate: DateTime(2026, 11, 20),
      );
      final breakdown = r.calculateOwedBreakdown(
        bills: [early, late],
        alreadyPaidPerBill: const {},
      );
      expect(breakdown, {BillType.electric: 15.0});
    });

    test('with percentageForType still skips pre-start bills', () {
      final r = makeRentor(startDate: DateTime(2026, 11, 13));
      final early = makeBill(
        type: BillType.electric,
        amount: 100,
        dueDate: DateTime(2026, 11, 12),
      );
      final late = makeBill(
        type: BillType.electric,
        amount: 100,
        dueDate: DateTime(2026, 11, 20),
      );
      final breakdown = r.calculateOwedBreakdown(
        bills: [early, late],
        alreadyPaidPerBill: const {},
        percentageForType: (_) => 20.0,
      );
      expect(breakdown, {BillType.electric: 20.0});
    });
  });
}
