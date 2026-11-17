import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/utils/bills/bill_recalculation.dart';

Bill bill({
  required String id,
  required BillType type,
  required double amount,
  required DateTime due,
  required PaymentStatus status,
  double? amountPaid,
}) => Bill(
  billId: id,
  company: 'Co',
  type: type,
  amount: amount,
  dueDate: due,
  status: status,
  notes: null,
  amountPaid: amountPaid,
);

Payment pay(String rentorId, double amount, List<String> billIds) => Payment(
  rentorId: rentorId,
  amountPaid: amount,
  paymentDate: DateTime(2025, 1, 18),
  billIds: billIds,
);

final joseph = Rentor(
  rentorId: 'J',
  name: 'J',
  defaultPercentage: 35,
  billPercentages: {
    BillType.electric: 35,
    BillType.gas: 35,
    BillType.water: 35,
  },
  excludedBillTypes: [
    BillType.internet,
    BillType.rent,
    BillType.phone,
    BillType.creditcard,
    BillType.personallineofcredit,
    BillType.other,
  ],
);

final ruth = Rentor(
  rentorId: 'R',
  name: 'R',
  defaultPercentage: 35,
  billPercentages: {
    BillType.electric: 35,
    BillType.gas: 35,
    BillType.internet: 50,
    BillType.water: 35,
  },
  excludedBillTypes: [
    BillType.rent,
    BillType.phone,
    BillType.creditcard,
    BillType.personallineofcredit,
    BillType.other,
  ],
);

Bill crown() => bill(
  id: 'crown',
  type: BillType.gas,
  amount: 44.43,
  due: DateTime(2025, 1, 1),
  status: PaymentStatus.partial,
  amountPaid: 16,
);

Bill alectra() => bill(
  id: 'alectra',
  type: BillType.electric,
  amount: 145.10,
  due: DateTime(2025, 1, 20),
  status: PaymentStatus.paid,
  amountPaid: 101,
);

Bill bell() => bill(
  id: 'bell',
  type: BillType.internet,
  amount: 188.71,
  due: DateTime(2025, 1, 23),
  status: PaymentStatus.paid,
  amountPaid: 94,
);

Bill enbridge() => bill(
  id: 'enbridge',
  type: BillType.gas,
  amount: 193.00,
  due: DateTime(2025, 1, 27),
  status: PaymentStatus.partial,
  amountPaid: 81,
);

// Both payments list bills out of due-date order on purpose.
final januaryPayments = [
  pay('J', 118, ['alectra', 'enbridge', 'crown']),
  pay('R', 174, ['enbridge', 'bell', 'alectra', 'crown']),
];

void main() {
  group('BillPaymentRecalculator', () {
    test('January 2025 worked example', () {
      final bills = [crown(), alectra(), bell(), enbridge()];
      final byId = {
        for (final r in BillPaymentRecalculator.recalculateAll(
          bills,
          januaryPayments,
          [joseph, ruth],
        ))
          r.bill.billId: r,
      };
      expect(byId['crown']!.amountPaid, 32);
      expect(byId['crown']!.status, PaymentStatus.paid);
      expect(byId['crown']!.changed, isTrue);
      expect(byId['alectra']!.amountPaid, 102);
      expect(byId['alectra']!.status, PaymentStatus.paid);
      expect(byId['bell']!.amountPaid, 94);
      expect(byId['bell']!.changed, isFalse);
      expect(byId['enbridge']!.amountPaid, 64);
      expect(byId['enbridge']!.status, PaymentStatus.partial);
    });

    test('recalculate one bill matches recalculateAll', () {
      final bills = [crown(), alectra(), bell(), enbridge()];
      final r =
          BillPaymentRecalculator.recalculate(
            bills[3],
            januaryPayments,
            bills,
            [joseph, ruth],
          )!;
      expect(r.amountPaid, 64);
    });

    test('a paid bill stays paid when its amount drops', () {
      final manual = bill(
        id: 'm',
        type: BillType.gas,
        amount: 44.43,
        due: DateTime(2025, 1, 1),
        status: PaymentStatus.paid,
        amountPaid: 44.43,
      );
      final r =
          BillPaymentRecalculator.recalculate(
            manual,
            [
              pay('J', 16, ['m']),
            ],
            [manual],
            [joseph, ruth],
          )!;
      expect(r.amountPaid, 16);
      expect(r.status, PaymentStatus.paid);
    });

    test('unknown-status bills are not touched and consume no money', () {
      final credit = bill(
        id: 'credit',
        type: BillType.gas,
        amount: -89.76,
        due: DateTime(2024, 12, 1),
        status: PaymentStatus.unknown,
      );
      final c = crown();
      final payments = [
        pay('J', 16, ['credit', 'crown']),
      ];
      expect(
        BillPaymentRecalculator.recalculate(
          credit,
          payments,
          [credit, c],
          [joseph, ruth],
        ),
        isNull,
      );
      expect(
        BillPaymentRecalculator.recalculate(
          c,
          payments,
          [credit, c],
          [joseph, ruth],
        )!.amountPaid,
        16,
      );
    });

    test('bills no payment lists are not touched', () {
      final c = crown();
      expect(
        BillPaymentRecalculator.recalculate(c, [], [c], [joseph, ruth]),
        isNull,
      );
      expect(
        BillPaymentRecalculator.recalculateAll([c], [], [joseph, ruth]),
        isEmpty,
      );
    });

    test('excluded bill gets nothing and money carries on', () {
      final b = bell();
      final c = crown();
      // Joseph excludes internet, so Bell is owed 0 and skipped; the money
      // reaches Crown Crest.
      final r = BillPaymentRecalculator.recalculateAll(
        [b, c],
        [
          pay('J', 16, ['bell', 'crown']),
        ],
        [joseph, ruth],
      );
      final byId = {for (final x in r) x.bill.billId: x};
      expect(byId['bell']!.amountPaid, 0);
      expect(byId['crown']!.amountPaid, 16);
    });

    test('bill due before the rentor starts gets nothing', () {
      final starter = Rentor(
        rentorId: 'L',
        name: 'L',
        defaultPercentage: 35,
        billPercentages: const {},
        startDate: DateTime(2025, 1, 15),
      );
      final c = crown();
      final e = enbridge();
      final byId = {
        for (final x in BillPaymentRecalculator.recalculateAll(
          [c, e],
          [
            pay('L', 68, ['crown', 'enbridge']),
          ],
          [starter],
        ))
          x.bill.billId: x,
      };
      expect(byId['crown']!.amountPaid, 0);
      expect(byId['enbridge']!.amountPaid, 68);
    });

    test('missing bill ids are ignored', () {
      final c = crown();
      final r =
          BillPaymentRecalculator.recalculate(
            c,
            [
              pay('J', 16, ['gone', 'crown']),
            ],
            [c],
            [joseph, ruth],
          )!;
      expect(r.amountPaid, 16);
    });

    test('payment with unknown rentor is ignored', () {
      final c = crown();
      expect(
        BillPaymentRecalculator.recalculate(
          c,
          [
            pay('nobody', 16, ['crown']),
          ],
          [c],
          [joseph, ruth],
        ),
        isNull,
      );
    });

    test('overpayment leftover stays unassigned', () {
      final c = crown();
      expect(
        BillPaymentRecalculator.recalculate(
          c,
          [
            pay('J', 50, ['crown']),
          ],
          [c],
          [joseph, ruth],
        )!.amountPaid,
        16,
      );
    });

    test('amounts are rounded to cents', () {
      // Shares round to $17, $83, $20; $119.07 leaves $19.07 for the newest
      // bill.
      final g1 = bill(
        id: 'g1',
        type: BillType.gas,
        amount: 47.60,
        due: DateTime(2026, 11, 1),
        status: PaymentStatus.unpaid,
      );
      final el = bill(
        id: 'el',
        type: BillType.electric,
        amount: 236.38,
        due: DateTime(2026, 11, 20),
        status: PaymentStatus.unpaid,
      );
      final g2 = bill(
        id: 'g2',
        type: BillType.gas,
        amount: 56.24,
        due: DateTime(2026, 11, 24),
        status: PaymentStatus.unpaid,
      );
      final byId = {
        for (final x in BillPaymentRecalculator.recalculateAll(
          [g1, el, g2],
          [
            pay('J', 119.07, ['g2', 'el', 'g1']),
          ],
          [joseph, ruth],
        ))
          x.bill.billId: x,
      };
      expect(byId['g1']!.amountPaid, 17);
      expect(byId['el']!.amountPaid, 83);
      expect(byId['g2']!.amountPaid, 19.07);
    });

    test('float noise alone is not a change', () {
      final g = bill(
        id: 'g',
        type: BillType.gas,
        amount: 47.60,
        due: DateTime(2026, 9, 1),
        status: PaymentStatus.paid,
        amountPaid: 33.81999999999999,
      );
      final r =
          BillPaymentRecalculator.recalculate(
            g,
            [
              pay('J', 17, ['g']),
              pay('R', 16.82, ['g']),
            ],
            [g],
            [joseph, ruth],
          )!;
      expect(r.amountPaid, 33.82);
      expect(r.changed, isFalse);
    });

    test('toUpdatedBill copies every field and applies the new values', () {
      final c = crown();
      final r = BillPaymentRecalculator.recalculateAll(
        [crown(), alectra(), bell(), enbridge()],
        januaryPayments,
        [joseph, ruth],
      ).firstWhere((x) => x.bill.billId == 'crown');
      final u = r.toUpdatedBill();
      expect(
        [u.billId, u.company, u.type, u.amount, u.dueDate, u.notes],
        [c.billId, c.company, c.type, c.amount, c.dueDate, c.notes],
      );
      expect(u.amountPaid, 32);
      expect(u.status, PaymentStatus.paid);
    });
  });
}
