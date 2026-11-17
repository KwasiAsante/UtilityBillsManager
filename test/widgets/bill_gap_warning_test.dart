import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/bills/bill_recalculation.dart';
import 'package:utility_bills_manager/widgets/bill_gap_warning.dart';

void main() {
  const gap = BillGap(billAmount: 193, paid: 64, owed: 136);

  Widget wrap() => const MaterialApp(
    home: Scaffold(body: BillGapWarning(gap: gap)),
  );

  testWidgets('shows a warning icon', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('tapping the icon explains the gap and OK closes it', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.byIcon(Icons.warning_amber_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Payment gap'), findsOneWidget);
    expect(find.text(gap.message), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(gap.message), findsNothing);
  });
}
