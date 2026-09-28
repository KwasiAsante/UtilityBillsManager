import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/dialogs/due_date_filter_sheet.dart';

void main() {
  group('DueDateFilterSheet system nav bar clearance (bottom sheet)', () {
    // AppBreakpoints.isWide treats width >= 600 as wide (dialog, not bottom
    // sheet) — use a narrow phone-portrait viewport so show() actually picks
    // the bottom-sheet branch this test targets.
    testWidgets('Apply button stays above the system nav bar / gesture inset',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const navBarHeight = 48.0;
      late Future<DueDateFilterResult?> dialogFuture;

      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(bottom: navBarHeight)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                dialogFuture = DueDateFilterSheet.show(
                  context,
                  availableYears: const [2025, 2026],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final applyButtonBottom =
          tester.getBottomLeft(find.widgetWithText(ElevatedButton, 'Apply'))
              .dy;

      expect(applyButtonBottom, lessThanOrEqualTo(screenHeight - navBarHeight));

      // Sanity: the sheet is actually usable (Apply pops with a result).
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(await dialogFuture, isNotNull);
    });
  });
}
