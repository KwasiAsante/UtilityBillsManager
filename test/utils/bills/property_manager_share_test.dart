import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/utils/bills/property_manager_share.dart';

Rentor rentor({
  String name = 'R',
  double defaultPercentage = 30,
  Map<BillType, double> billPercentages = const {},
  List<BillType> excluded = const [],
  DateTime? startDate,
  String? email,
}) => Rentor(
  name: name,
  email: email,
  defaultPercentage: defaultPercentage,
  billPercentages: billPercentages,
  excludedBillTypes: excluded,
  startDate: startDate,
);

Bill bill({
  BillType type = BillType.electric,
  double amount = 100,
  DateTime? dueDate,
  PaymentStatus status = PaymentStatus.unpaid,
  double? amountPaid,
}) => Bill(
  company: 'Co',
  type: type,
  amount: amount,
  dueDate: dueDate ?? DateTime(2026, 11, 20),
  status: status,
  notes: null,
  amountPaid: amountPaid,
);

void main() {
  final d = DateTime(2026, 11, 20);

  Rentor a() => rentor(
    name: 'A',
    defaultPercentage: 30,
    excluded: [
      BillType.internet,
      BillType.rent,
      BillType.phone,
      BillType.creditcard,
      BillType.personallineofcredit,
    ],
  );
  Rentor b({DateTime? startDate}) => rentor(
    name: 'B',
    defaultPercentage: 30,
    billPercentages: {BillType.internet: 33},
    excluded: [
      BillType.rent,
      BillType.phone,
      BillType.creditcard,
      BillType.personallineofcredit,
    ],
    startDate: startDate,
  );
  Rentor c({DateTime? startDate}) => rentor(
    name: 'C',
    defaultPercentage: 15,
    billPercentages: {BillType.internet: 33},
    excluded: [
      BillType.phone,
      BillType.creditcard,
      BillType.personallineofcredit,
    ],
    startDate: startDate,
  );
  final abc = [a(), b(), c()];

  group('shareFor', () {
    test('worked example: gas 25, electric 25, internet 34', () {
      expect(PropertyManagerShare.shareFor(BillType.gas, d, abc), 25);
      expect(PropertyManagerShare.shareFor(BillType.electric, d, abc), 25);
      expect(PropertyManagerShare.shareFor(BillType.internet, d, abc), 34);
    });

    test('rent covered via C default -> 85', () {
      expect(PropertyManagerShare.shareFor(BillType.rent, d, abc), 85);
    });

    test('type excluded by all -> null', () {
      expect(PropertyManagerShare.shareFor(BillType.phone, d, abc), isNull);
    });

    test('no rentors -> null', () {
      expect(PropertyManagerShare.shareFor(BillType.gas, d, []), isNull);
    });

    test('no rounding: 33.3 + 33.3 -> 33.4', () {
      final rentors = [
        rentor(billPercentages: {BillType.internet: 33.3}),
        rentor(billPercentages: {BillType.internet: 33.3}),
      ];
      expect(
        PropertyManagerShare.shareFor(BillType.internet, d, rentors),
        closeTo(33.4, 1e-9),
      );
    });

    test('rentor with future startDate does not count', () {
      final rentors = [a(), b(), c(startDate: d.add(const Duration(days: 1)))];
      expect(PropertyManagerShare.shareFor(BillType.gas, d, rentors), 40);
    });

    test(
      'rentor whose only active-covering rentor is not yet started -> null',
      () {
        final rentors = [c(startDate: d.add(const Duration(days: 1)))];
        expect(PropertyManagerShare.shareFor(BillType.gas, d, rentors), isNull);
      },
    );

    test('current data reproduces 30/50', () {
      final joseph = rentor(
        name: 'Joseph',
        defaultPercentage: 35,
        excluded: [
          BillType.internet,
          BillType.rent,
          BillType.phone,
          BillType.creditcard,
          BillType.personallineofcredit,
          BillType.other,
        ],
      );
      final ruth = rentor(
        name: 'Ruth',
        defaultPercentage: 35,
        billPercentages: {BillType.internet: 50},
        excluded: [
          BillType.rent,
          BillType.phone,
          BillType.creditcard,
          BillType.personallineofcredit,
        ],
      );
      final rentors = [joseph, ruth];
      for (final t in [BillType.electric, BillType.gas, BillType.water]) {
        expect(PropertyManagerShare.shareFor(t, d, rentors), 30);
      }
      expect(PropertyManagerShare.shareFor(BillType.internet, d, rentors), 50);
    });
  });

  group('sharesAsOf', () {
    test('lists only covered types', () {
      expect(PropertyManagerShare.sharesAsOf(d, abc), {
        BillType.electric: 25,
        BillType.gas: 25,
        BillType.water: 25,
        BillType.other: 25,
        BillType.internet: 34,
        BillType.rent: 85,
      });
    });
  });

  group('isConsideredPaid', () {
    test('electric 100, paid 75, share 25 -> true', () {
      final bl = bill(status: PaymentStatus.partial, amountPaid: 75);
      expect(PropertyManagerShare.isConsideredPaid(bl, abc), isTrue);
    });

    test(
      'electric 100, paid 73.40, share 25, 3 rentors -> false '
      '(unpaid 26.60 > 25 + 1.50)',
      () {
        final bl = bill(status: PaymentStatus.partial, amountPaid: 73.40);
        expect(PropertyManagerShare.isConsideredPaid(bl, abc), isFalse);
      },
    );

    test('three rentors: tolerance is \$1.50, so unpaid 26.50 -> true', () {
      final bl = bill(status: PaymentStatus.partial, amountPaid: 73.50);
      expect(PropertyManagerShare.isConsideredPaid(bl, abc), isTrue);
    });

    test('two rentors: tolerance stays exactly \$1.00', () {
      // A 35 + B 35 -> PM share 30; threshold 30 + 1.00.
      final rentors = [
        rentor(defaultPercentage: 35),
        rentor(defaultPercentage: 35),
      ];
      final at = bill(status: PaymentStatus.partial, amountPaid: 69.00);
      final over = bill(status: PaymentStatus.partial, amountPaid: 68.90);
      expect(PropertyManagerShare.isConsideredPaid(at, rentors), isTrue);
      expect(PropertyManagerShare.isConsideredPaid(over, rentors), isFalse);
    });

    test('three rentors absorb per-rentor whole-dollar rounding '
        '(\$101.40, 35/35/15, each pays exact share -> credited 85)', () {
      final rentors = [
        rentor(defaultPercentage: 35),
        rentor(defaultPercentage: 35),
        rentor(defaultPercentage: 15),
      ];
      // Each rentor's credit is capped at round(101.40 * pct) = 35 / 35 / 15.
      final bl = bill(
        amount: 101.40,
        status: PaymentStatus.partial,
        amountPaid: 85,
      );
      expect(PropertyManagerShare.isConsideredPaid(bl, rentors), isTrue);
    });

    test('rentors excluding the type or not yet started do not widen the '
        'tolerance', () {
      final rentors = [
        rentor(defaultPercentage: 35),
        rentor(defaultPercentage: 35),
        rentor(defaultPercentage: 15, excluded: [BillType.electric]),
        rentor(defaultPercentage: 15, startDate: DateTime(2027, 1, 1)),
      ];
      // Only 2 rentors count: share 30, tolerance 1.00.
      final over = bill(status: PaymentStatus.partial, amountPaid: 68.90);
      expect(PropertyManagerShare.isConsideredPaid(over, rentors), isFalse);
    });

    test('electric 100, paid 74.50, share 25 -> true (\$1 tolerance)', () {
      final bl = bill(status: PaymentStatus.partial, amountPaid: 74.50);
      expect(PropertyManagerShare.isConsideredPaid(bl, abc), isTrue);
    });

    test('fully paid bill is considered paid', () {
      final bl = bill(status: PaymentStatus.paid, amountPaid: 100);
      expect(PropertyManagerShare.isConsideredPaid(bl, abc), isTrue);
    });

    test('rentors total 110% -> needs full payment; unpaid 0.80 -> true, '
        'unpaid 1.20 -> false', () {
      final rentors = [
        rentor(defaultPercentage: 60),
        rentor(defaultPercentage: 50),
      ];
      expect(
        PropertyManagerShare.shareFor(BillType.electric, d, rentors),
        closeTo(-10, 1e-9),
      );
      final near = bill(status: PaymentStatus.partial, amountPaid: 99.20);
      final far = bill(status: PaymentStatus.partial, amountPaid: 98.80);
      expect(PropertyManagerShare.isConsideredPaid(near, rentors), isTrue);
      expect(PropertyManagerShare.isConsideredPaid(far, rentors), isFalse);
    });

    test('uncovered type -> false', () {
      final bl = bill(
        type: BillType.phone,
        status: PaymentStatus.paid,
        amountPaid: 100,
      );
      expect(PropertyManagerShare.isConsideredPaid(bl, abc), isFalse);
    });
  });

  group('paidAmount', () {
    test('amountPaid wins regardless of status', () {
      expect(
        PropertyManagerShare.paidAmount(
          bill(status: PaymentStatus.unpaid, amountPaid: 85),
        ),
        85,
      );
      expect(
        PropertyManagerShare.paidAmount(
          bill(status: PaymentStatus.paid, amountPaid: 70),
        ),
        70,
      );
      expect(
        PropertyManagerShare.paidAmount(
          bill(status: PaymentStatus.partial, amountPaid: 40),
        ),
        40,
      );
    });

    test('paid with null amountPaid falls back to amount', () {
      expect(
        PropertyManagerShare.paidAmount(bill(status: PaymentStatus.paid)),
        100,
      );
    });

    test('partial, unpaid and unknown with null amountPaid are 0', () {
      expect(
        PropertyManagerShare.paidAmount(bill(status: PaymentStatus.partial)),
        0,
      );
      expect(
        PropertyManagerShare.paidAmount(bill(status: PaymentStatus.unpaid)),
        0,
      );
      expect(
        PropertyManagerShare.paidAmount(bill(status: PaymentStatus.unknown)),
        0,
      );
    });
  });

  group('recomputeStatus', () {
    test('paid bill with amountPaid null stays paid', () {
      final bl = bill(status: PaymentStatus.paid);
      expect(PropertyManagerShare.recomputeStatus(bl, abc), PaymentStatus.paid);
    });

    test('paid bill no longer meeting new share -> partial', () {
      // Share is 0 (rentors total 100): needs full payment; 50 paid.
      final rentors = [rentor(defaultPercentage: 100)];
      final bl = bill(status: PaymentStatus.paid, amountPaid: 50);
      expect(
        PropertyManagerShare.recomputeStatus(bl, rentors),
        PaymentStatus.partial,
      );
    });

    test('amountPaid 0 and not considered paid -> unpaid', () {
      final bl = bill(status: PaymentStatus.partial, amountPaid: 0);
      expect(
        PropertyManagerShare.recomputeStatus(bl, abc),
        PaymentStatus.unpaid,
      );
    });

    test('paid bill (amountPaid null) of an uncovered type stays paid', () {
      final bl = bill(type: BillType.phone, status: PaymentStatus.paid);
      expect(PropertyManagerShare.recomputeStatus(bl, abc), PaymentStatus.paid);
    });

    test('partial bill of an uncovered type stays partial', () {
      final bl = bill(
        type: BillType.phone,
        status: PaymentStatus.partial,
        amountPaid: 20,
      );
      expect(
        PropertyManagerShare.recomputeStatus(bl, abc),
        PaymentStatus.partial,
      );
    });

    test('unknown-status bill with a high share stays unknown', () {
      final rentors = [rentor(defaultPercentage: 10)];
      final bl = bill(status: PaymentStatus.unknown);
      expect(PropertyManagerShare.shareFor(bl.type, bl.dueDate, rentors), 90);
      expect(
        PropertyManagerShare.recomputeStatus(bl, rentors),
        PaymentStatus.unknown,
      );
    });

    test('uncovered type with nothing paid -> unpaid', () {
      final bl = bill(type: BillType.phone, status: PaymentStatus.unpaid);
      expect(
        PropertyManagerShare.recomputeStatus(bl, abc),
        PaymentStatus.unpaid,
      );
    });
  });

  group('shareInputsChanged', () {
    test('name/email change -> false', () {
      final before = rentor(name: 'A', email: 'a@x.com');
      final after = rentor(name: 'B', email: 'b@x.com');
      expect(PropertyManagerShare.shareInputsChanged(before, after), isFalse);
    });

    test('startDate change -> true', () {
      final before = rentor(startDate: DateTime(2026, 1, 1));
      final after = rentor(startDate: DateTime(2026, 2, 1));
      expect(PropertyManagerShare.shareInputsChanged(before, after), isTrue);
      expect(PropertyManagerShare.shareInputsChanged(rentor(), after), isTrue);
    });

    test('defaultPercentage change -> true', () {
      expect(
        PropertyManagerShare.shareInputsChanged(
          rentor(defaultPercentage: 30),
          rentor(defaultPercentage: 35),
        ),
        isTrue,
      );
    });

    test('billPercentages change -> true', () {
      expect(
        PropertyManagerShare.shareInputsChanged(
          rentor(billPercentages: {BillType.gas: 10}),
          rentor(billPercentages: {BillType.gas: 20}),
        ),
        isTrue,
      );
      expect(
        PropertyManagerShare.shareInputsChanged(
          rentor(billPercentages: {BillType.gas: 10}),
          rentor(billPercentages: {}),
        ),
        isTrue,
      );
    });

    test('excludedBillTypes change -> true; reorder -> false', () {
      expect(
        PropertyManagerShare.shareInputsChanged(
          rentor(excluded: [BillType.gas]),
          rentor(excluded: [BillType.gas, BillType.water]),
        ),
        isTrue,
      );
      expect(
        PropertyManagerShare.shareInputsChanged(
          rentor(excluded: [BillType.gas, BillType.water]),
          rentor(excluded: [BillType.water, BillType.gas]),
        ),
        isFalse,
      );
    });
  });

  group('billsAffectedByChange', () {
    final jan = bill(dueDate: DateTime(2026, 1, 15));
    final feb = bill(dueDate: DateTime(2026, 2, 15));
    final mar = bill(dueDate: DateTime(2026, 3, 15));
    final marRent = bill(type: BillType.rent, dueDate: DateTime(2026, 3, 15));

    test(
      'new rentor: only bills due on/after startDate, not excluded types',
      () {
        final after = rentor(
          startDate: DateTime(2026, 2, 15),
          excluded: [BillType.rent],
        );
        final result = PropertyManagerShare.billsAffectedByChange(null, after, [
          jan,
          feb,
          mar,
          marRent,
        ]);
        expect(result, [feb, mar]);
      },
    );

    test('new rentor with null startDate: all non-excluded bills', () {
      final after = rentor(excluded: [BillType.rent]);
      final result = PropertyManagerShare.billsAffectedByChange(null, after, [
        jan,
        feb,
        mar,
        marRent,
      ]);
      expect(result, [jan, feb, mar]);
    });

    test(
      'edit moving startDate later: bills between old and new start included',
      () {
        final before = rentor(startDate: DateTime(2026, 1, 1));
        final after = rentor(startDate: DateTime(2026, 3, 1));
        final dec = bill(dueDate: DateTime(2025, 12, 31));
        final result = PropertyManagerShare.billsAffectedByChange(
          before,
          after,
          [dec, jan, feb, mar],
        );
        expect(result, [jan, feb, mar]);
      },
    );

    test('edit with before.startDate null: no lower bound', () {
      final before = rentor();
      final after = rentor(startDate: DateTime(2026, 3, 1));
      final result = PropertyManagerShare.billsAffectedByChange(before, after, [
        jan,
        feb,
        mar,
      ]);
      expect(result, [jan, feb, mar]);
    });

    test('edit clearing startDate: no lower bound', () {
      final before = rentor(startDate: DateTime(2026, 3, 1));
      final after = rentor();
      final result = PropertyManagerShare.billsAffectedByChange(before, after, [
        jan,
        feb,
        mar,
      ]);
      expect(result, [jan, feb, mar]);
    });

    test('due on the start day (date-only) is included', () {
      final after = rentor(startDate: DateTime(2026, 2, 15, 13, 30));
      final bl = bill(dueDate: DateTime(2026, 2, 15, 8));
      expect(PropertyManagerShare.billsAffectedByChange(null, after, [bl]), [
        bl,
      ]);
    });

    test('edit adding an exclusion: bills of that type included', () {
      final before = rentor();
      final after = rentor(excluded: [BillType.rent]);
      final result = PropertyManagerShare.billsAffectedByChange(before, after, [
        jan,
        marRent,
      ]);
      expect(result, [jan, marRent]);
    });

    test('type excluded by both before and after is not affected', () {
      final before = rentor(excluded: [BillType.rent]);
      final after = rentor(excluded: [BillType.rent], defaultPercentage: 40);
      final result = PropertyManagerShare.billsAffectedByChange(before, after, [
        jan,
        marRent,
      ]);
      expect(result, [jan]);
    });

    test('unknown-status bills never included', () {
      final unknown = bill(
        status: PaymentStatus.unknown,
        dueDate: DateTime(2026, 3, 15),
      );
      final result = PropertyManagerShare.billsAffectedByChange(
        null,
        rentor(),
        [unknown, mar],
      );
      expect(result, [mar]);
    });
  });
}
