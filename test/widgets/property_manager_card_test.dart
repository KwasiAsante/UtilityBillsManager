import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/widgets/property_manager_card.dart';

Rentor rentor({
  String name = 'R',
  double defaultPercentage = 30,
  Map<BillType, double> billPercentages = const {},
  List<BillType> excluded = const [],
  DateTime? startDate,
}) => Rentor(
  name: name,
  defaultPercentage: defaultPercentage,
  billPercentages: billPercentages,
  excludedBillTypes: excluded,
  startDate: startDate,
);

Widget wrap(List<Rentor> rentors, {DateTime? asOf}) => MaterialApp(
  home: Scaffold(body: PropertyManagerCard(rentors: rentors, asOf: asOf)),
);

void main() {
  final asOf = DateTime(2026, 11, 20);

  // Worked example: A, B, C.
  List<Rentor> abc({DateTime? cStart}) => [
    rentor(
      name: 'A',
      defaultPercentage: 30,
      excluded: [
        BillType.internet,
        BillType.rent,
        BillType.phone,
        BillType.creditcard,
        BillType.personallineofcredit,
      ],
    ),
    rentor(
      name: 'B',
      defaultPercentage: 30,
      billPercentages: {BillType.internet: 33},
      excluded: [
        BillType.rent,
        BillType.phone,
        BillType.creditcard,
        BillType.personallineofcredit,
      ],
    ),
    rentor(
      name: 'C',
      defaultPercentage: 15,
      billPercentages: {BillType.internet: 33},
      excluded: [
        BillType.phone,
        BillType.creditcard,
        BillType.personallineofcredit,
      ],
      startDate: cStart,
    ),
  ];

  testWidgets('shows title and subtitle', (tester) async {
    await tester.pumpWidget(wrap(abc(), asOf: asOf));
    expect(find.text('Property Manager'), findsOneWidget);
    expect(find.text("Covers whatever the rentors don't pay"), findsOneWidget);
  });

  testWidgets('shows covered types with 2-decimal shares', (tester) async {
    await tester.pumpWidget(wrap(abc(), asOf: asOf));
    expect(find.text('Gas  25.00%'), findsOneWidget);
    expect(find.text('Internet  34.00%'), findsOneWidget);
    expect(find.text('Rent  85.00%'), findsOneWidget);
    expect(find.textContaining('Phone'), findsNothing);
    expect(find.textContaining('add up to 100% or more'), findsNothing);
  });

  testWidgets('shows warning naming types at or over 100%', (tester) async {
    final rentors = [
      rentor(name: 'A', billPercentages: {BillType.gas: 60}),
      rentor(name: 'B', billPercentages: {BillType.gas: 50}),
    ];
    await tester.pumpWidget(wrap(rentors, asOf: asOf));
    expect(find.text('Gas  -10.00%'), findsOneWidget);
    expect(
      find.textContaining('Rentor percentages for Gas add up to 100% or more'),
      findsOneWidget,
    );
  });

  Widget gasRow(List<double> gasPercentages) {
    return wrap([
      for (var i = 0; i < gasPercentages.length; i++)
        rentor(
          name: 'R$i',
          defaultPercentage: 10,
          billPercentages: {BillType.gas: gasPercentages[i]},
        ),
    ], asOf: asOf);
  }

  testWidgets('positive float noise at a true 100% shows 0.00% and warns', (
    tester,
  ) async {
    // 100 - (33.3 + 33.4 + 33.3) is +1.4e-14 in doubles, not 0.
    await tester.pumpWidget(gasRow([33.3, 33.4, 33.3]));
    expect(find.text('Gas  0.00%'), findsOneWidget);
    expect(
      find.textContaining('Rentor percentages for Gas add up to 100% or more'),
      findsOneWidget,
    );
  });

  testWidgets('negative float noise at a true 100% shows 0.00%, not -0.00%', (
    tester,
  ) async {
    // 100 - (99.4 + 0.2 + 0.4) is -1.4e-14 in doubles, not 0.
    await tester.pumpWidget(gasRow([99.4, 0.2, 0.4]));
    expect(find.text('Gas  0.00%'), findsOneWidget);
    expect(find.text('Gas  -0.00%'), findsNothing);
    expect(
      find.textContaining('Rentor percentages for Gas add up to 100% or more'),
      findsOneWidget,
    );
  });

  testWidgets('warning lists multiple types comma-separated', (tester) async {
    final rentors = [
      rentor(
        name: 'A',
        defaultPercentage: 70,
        excluded:
            BillType.values
                .where((t) => t != BillType.electric && t != BillType.gas)
                .toList(),
      ),
      rentor(
        name: 'B',
        defaultPercentage: 30,
        excluded:
            BillType.values
                .where((t) => t != BillType.electric && t != BillType.gas)
                .toList(),
      ),
    ];
    await tester.pumpWidget(wrap(rentors, asOf: asOf));
    expect(
      find.text(
        'Rentor percentages for Electric, Gas add up to 100% or more. '
        'Update the rentor percentages.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('rentor with future startDate is ignored', (tester) async {
    await tester.pumpWidget(
      wrap(abc(cStart: DateTime(2027, 1, 1)), asOf: asOf),
    );
    // Without C: gas 100-60 = 40, internet 100-33 = 67, rent not covered.
    expect(find.text('Gas  40.00%'), findsOneWidget);
    expect(find.text('Internet  34.00%'), findsNothing);
    expect(find.text('Internet  67.00%'), findsOneWidget);
    expect(find.textContaining('Rent'), findsNothing);
  });

  testWidgets('renders nothing when no types are covered', (tester) async {
    await tester.pumpWidget(wrap(const [], asOf: asOf));
    expect(find.text('Property Manager'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });
}
