import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/data/repositories/bills_repository.dart';
import 'package:utility_bills_manager/screens/rentors/add_edit_rentor_screen.dart';

Widget wrap(Rentor? rentor) =>
    MaterialApp(home: AddEditRentorScreen(rentor: rentor));

Finder startDateField() => find.widgetWithText(TextFormField, 'Start date');

String startDateText(WidgetTester tester) {
  final field = tester.widget<TextFormField>(startDateField());
  return field.controller!.text;
}

Rentor rentorWith({DateTime? startDate}) => Rentor(
  name: 'Sam',
  defaultPercentage: 30,
  billPercentages: const {},
  startDate: startDate,
);

void main() {
  setUp(() {
    // Editing a rentor loads eligible bills after the first frame and calls
    // BillsRepository.reload() (database/network) when the cache is empty.
    // Seeding the in-memory cache makes the screen skip that reload, so these
    // tests only exercise the form.
    BillsRepository().bills = [
      Bill(
        company: 'Co',
        type: BillType.gas,
        amount: 10,
        dueDate: DateTime(2020, 1, 1),
        status: PaymentStatus.paid,
        notes: null,
      ),
    ];
  });

  tearDown(() {
    BillsRepository().bills = [];
  });

  testWidgets('new rentor: start date defaults to today', (tester) async {
    await tester.pumpWidget(wrap(null));
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    expect(startDateText(tester), today);
  });

  testWidgets('shows helper text', (tester) async {
    await tester.pumpWidget(wrap(null));
    expect(
      find.text(
        "Bills due before this date aren't split with this rentor. "
        "Leave empty if they've always been here.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('editing rentor with null startDate shows empty field', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(rentorWith(startDate: null)));
    await tester.pump();
    expect(startDateText(tester), '');
  });

  testWidgets('editing rentor shows its stored startDate', (tester) async {
    await tester.pumpWidget(wrap(rentorWith(startDate: DateTime(2026, 3, 5))));
    await tester.pump();
    expect(startDateText(tester), '2026-03-05');
  });

  testWidgets('clearing the start date leaves it empty', (tester) async {
    await tester.pumpWidget(wrap(null));
    expect(startDateText(tester), isNotEmpty);

    await tester.ensureVisible(find.byIcon(Icons.clear));
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(startDateText(tester), '');
    // The clear button goes away once there is nothing to clear.
    expect(find.byIcon(Icons.clear), findsNothing);
  });
  testWidgets(
    'date picker opens when the stored start date is far in the future',
    (tester) async {
      final future = DateTime(DateTime.now().year + 10, 6, 15);
      await tester.pumpWidget(wrap(rentorWith(startDate: future)));
      await tester.pump();

      await tester.ensureVisible(startDateField());
      await tester.tap(startDateField());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    },
  );
}
