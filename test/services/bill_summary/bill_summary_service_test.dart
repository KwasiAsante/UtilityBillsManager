import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/services/bill_summary/bill_summary_service.dart';

void main() {
  late BillSummaryService service;

  setUp(() {
    service = BillSummaryService();
  });

  Bill makeBill({
    required BillType type,
    required double amount,
    required DateTime dueDate,
    PaymentStatus status = PaymentStatus.unpaid,
  }) =>
      Bill(
        company: 'Test Co',
        type: type,
        amount: amount,
        dueDate: dueDate,
        status: status,
        notes: null,
      );

  Rentor makeRentor({
    String name = 'Alex Johnson',
    double defaultPercentage = 50.0,
    List<BillType> excluded = const [],
  }) =>
      Rentor(
        name: name,
        defaultPercentage: defaultPercentage,
        billPercentages: const {},
        excludedBillTypes: excluded,
      );

  group('getEligibleBills', () {
    test('excludes paid bills', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
        status: PaymentStatus.paid,
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('excludes bills outside current month (non-water)', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 3, 15),
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('excludes bills for excluded bill types', () {
      final rentor = makeRentor(excluded: [BillType.electric]);
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('includes unpaid bill due this month', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, hasLength(1));
    });

    test('includes partial bill due this month', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
        status: PaymentStatus.partial,
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, hasLength(1));
    });

    test('includes unknown-status bill due this month', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
        status: PaymentStatus.unknown,
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, hasLength(1));
    });

    test('includes water bill due next month', () {
      final rentor = makeRentor();
      final waterBill = makeBill(
        type: BillType.water,
        amount: 80.0,
        dueDate: DateTime(2026, 5, 1), // due May, current month is April
      );
      final result = service.getEligibleBills(rentor, [waterBill],
          now: DateTime(2026, 4, 15));
      expect(result, hasLength(1));
    });

    test('excludes non-water bill due next month', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 5, 15), // due May, current month is April
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('handles December → January year boundary for water bill', () {
      final rentor = makeRentor();
      final waterBill = makeBill(
        type: BillType.water,
        amount: 80.0,
        dueDate: DateTime(2027, 1, 1), // due January 2027, current month is December 2026
      );
      final result = service.getEligibleBills(rentor, [waterBill],
          now: DateTime(2026, 12, 15));
      expect(result, hasLength(1));
    });
  });

  group('isSettledForMonth', () {
    test('returns true for empty list', () {
      expect(service.isSettledForMonth([]), isTrue);
    });

    test('returns false for non-empty list', () {
      final bill = makeBill(
          type: BillType.electric,
          amount: 100.0,
          dueDate: DateTime(2026, 4, 15));
      expect(service.isSettledForMonth([bill]), isFalse);
    });
  });

  group('generateMessage — greeting', () {
    test('Good morning when hour < 12', () {
      final rentor = makeRentor();
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 8));
      expect(msg, startsWith('Good morning'));
    });

    test('Good afternoon when hour is 12–16', () {
      final rentor = makeRentor();
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 14));
      expect(msg, startsWith('Good afternoon'));
    });

    test('Good evening when hour >= 17', () {
      final rentor = makeRentor();
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 19));
      expect(msg, startsWith('Good evening'));
    });
  });

  group('generateMessage — format', () {
    test('returns empty string for empty bill list', () {
      final rentor = makeRentor();
      expect(service.generateMessage(rentor, []), equals(''));
    });

    test('uses first name only', () {
      final rentor = makeRentor(name: 'Alex Johnson');
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 8));
      expect(msg, contains('Alex'));
      expect(msg, isNot(contains('Johnson')));
    });

    test('single regular bill', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      // (90 * 50/100).round() = 45
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 8));
      expect(msg,
          equals('Good morning Alex, the electric bill is \$45.00 due April 15th.'));
    });

    test('two regular bills joined with "and", no comma', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final electric = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 10));
      final gas = makeBill(
          type: BillType.gas, amount: 60.0, dueDate: DateTime(2026, 4, 20));
      // avg day = (10+20)/2 = 15 → April 15th
      // electric: 45.00, gas: 30.00
      final msg = service.generateMessage(rentor, [electric, gas],
          now: DateTime(2026, 4, 1, 8));
      expect(
          msg,
          equals(
              'Good morning Alex, the electric bill is \$45.00 and gas bill is \$30.00 due April 15th.'));
    });

    test('three regular bills: Oxford comma before last', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final electric = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final gas = makeBill(
          type: BillType.gas, amount: 60.0, dueDate: DateTime(2026, 4, 15));
      final internet = makeBill(
          type: BillType.internet,
          amount: 50.0,
          dueDate: DateTime(2026, 4, 15));
      // electric: 45.00, gas: 30.00, internet: 25.00
      final msg = service.generateMessage(rentor, [electric, gas, internet],
          now: DateTime(2026, 4, 1, 8));
      expect(
          msg,
          equals(
              'Good morning Alex, the electric bill is \$45.00, gas bill is \$30.00, and internet bill is \$25.00 due April 15th.'));
    });

    test('water bill only', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final water = makeBill(
          type: BillType.water, amount: 80.0, dueDate: DateTime(2026, 5, 1));
      // (80 * 0.5).round() = 40
      final msg = service.generateMessage(rentor, [water],
          now: DateTime(2026, 4, 15, 8));
      expect(msg,
          equals('Good morning Alex, the water bill is \$40.00 due May 1st.'));
    });

    test('regular bills + water bill', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final electric = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final water = makeBill(
          type: BillType.water, amount: 80.0, dueDate: DateTime(2026, 5, 1));
      final msg = service.generateMessage(rentor, [electric, water],
          now: DateTime(2026, 4, 15, 8));
      expect(
          msg,
          equals(
              'Good morning Alex, the electric bill is \$45.00 due April 15th. The water bill is \$40.00 due May 1st.'));
    });
  });

  group('generateMessage — ordinal date suffixes', () {
    Bill billDue(int day) => makeBill(
        type: BillType.electric,
        amount: 90.0,
        dueDate: DateTime(2026, 4, day));
    final rentor = makeRentor(defaultPercentage: 50.0);

    test('1st', () {
      expect(
          service.generateMessage(rentor, [billDue(1)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 1st'));
    });
    test('2nd', () {
      expect(
          service.generateMessage(rentor, [billDue(2)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 2nd'));
    });
    test('3rd', () {
      expect(
          service.generateMessage(rentor, [billDue(3)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 3rd'));
    });
    test('11th (special case)', () {
      expect(
          service.generateMessage(rentor, [billDue(11)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 11th'));
    });
    test('12th (special case)', () {
      expect(
          service.generateMessage(rentor, [billDue(12)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 12th'));
    });
    test('13th (special case)', () {
      expect(
          service.generateMessage(rentor, [billDue(13)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 13th'));
    });
    test('21st', () {
      expect(
          service.generateMessage(rentor, [billDue(21)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 21st'));
    });
    test('22nd', () {
      expect(
          service.generateMessage(rentor, [billDue(22)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 22nd'));
    });
    test('23rd', () {
      expect(
          service.generateMessage(rentor, [billDue(23)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 23rd'));
    });
  });
}
