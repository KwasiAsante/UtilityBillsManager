import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/dialogs/export_month_picker_dialog.dart';

void main() {
  late Future<ExportMonthPickerResult?> dialogFuture;

  Widget buildApp({
    List<String> availableMonths = const ['May 2026', 'April 2026'],
    bool showCombineOption = false,
    bool? isWebOverride,
    EdgeInsets systemInsets = EdgeInsets.zero,
  }) {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: systemInsets),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () {
              dialogFuture = ExportMonthPickerDialog.show(
                context,
                availableMonths: availableMonths,
                showCombineOption: showCombineOption,
                isWebOverride: isWebOverride,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    List<String> availableMonths = const ['May 2026', 'April 2026'],
    bool showCombineOption = false,
    bool? isWebOverride,
    EdgeInsets systemInsets = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(buildApp(
      availableMonths: availableMonths,
      showCombineOption: showCombineOption,
      isWebOverride: isWebOverride,
      systemInsets: systemInsets,
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('ExportMonthPickerDialog initial state', () {
    testWidgets('lists every available month, all pre-checked',
        (tester) async {
      await openDialog(tester);
      expect(find.text('May 2026'), findsOneWidget);
      expect(find.text('April 2026'), findsOneWidget);
      final checkboxes = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .where((c) => c.value == true);
      expect(checkboxes.length, greaterThanOrEqualTo(2));
    });

    testWidgets('hides the combine-workbook option when showCombineOption is false',
        (tester) async {
      await openDialog(tester, showCombineOption: false);
      expect(find.textContaining('Combine into'), findsNothing);
    });

    testWidgets('shows the combine-workbook option when showCombineOption is true',
        (tester) async {
      await openDialog(tester, showCombineOption: true);
      expect(find.textContaining('Combine into'), findsOneWidget);
    });
  });

  group('ExportMonthPickerDialog selection', () {
    testWidgets('tapping Export with everything pre-checked returns all months',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result, isNotNull);
      expect(result!.selectedMonths, equals(['May 2026', 'April 2026']));
    });

    testWidgets('unchecking a month excludes it from the result',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('April 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result!.selectedMonths, equals(['May 2026']));
    });

    testWidgets('Clear All then re-selecting one month exports only that month',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('May 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result!.selectedMonths, equals(['May 2026']));
    });

    testWidgets('Export is disabled when no months are selected',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();
      final exportButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Export'),
      );
      expect(exportButton.onPressed, isNull);
    });

    testWidgets('Cancel returns null', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result, isNull);
    });

    testWidgets('combineAsWorkbook defaults to true and reflects the checkbox',
        (tester) async {
      await openDialog(tester, showCombineOption: true);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result!.combineAsWorkbook, isTrue);
    });

    testWidgets('unchecking combine-workbook is reflected in the result',
        (tester) async {
      await openDialog(tester, showCombineOption: true);
      await tester.tap(find.textContaining('Combine into'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result!.combineAsWorkbook, isFalse);
    });
  });

  group('ExportMonthPickerDialog web file-limit cap', () {
    final elevenMonths = List.generate(11, (i) => 'Month $i');

    CheckboxListTile tileFor(WidgetTester tester, String month) {
      return tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text(month),
          matching: find.byType(CheckboxListTile),
        ),
      );
    }

    testWidgets(
        'auto-trims to 10 and disables the rest when combine is turned off '
        'with more than 10 months available', (tester) async {
      await openDialog(
        tester,
        availableMonths: elevenMonths,
        showCombineOption: true,
        isWebOverride: true,
      );
      await tester.tap(find.textContaining('Combine into'));
      await tester.pumpAndSettle();

      final month10 = tileFor(tester, 'Month 10');
      expect(month10.value, isFalse);
      expect(month10.onChanged, isNull);

      final month0 = tileFor(tester, 'Month 0');
      expect(month0.value, isTrue);
      expect(month0.onChanged, isNotNull);
    });

    testWidgets('unchecking a selected month re-enables the disabled ones',
        (tester) async {
      await openDialog(
        tester,
        availableMonths: elevenMonths,
        showCombineOption: true,
        isWebOverride: true,
      );
      await tester.tap(find.textContaining('Combine into'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month 5'));
      await tester.pumpAndSettle();

      expect(tileFor(tester, 'Month 10').onChanged, isNotNull);
    });

    testWidgets('Select All caps at 10 months when combine is off',
        (tester) async {
      await openDialog(
        tester,
        availableMonths: elevenMonths,
        showCombineOption: true,
        isWebOverride: true,
      );
      await tester.tap(find.textContaining('Combine into'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Export'));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      final result = await dialogFuture;
      expect(result!.selectedMonths.length, equals(10));
      expect(result.selectedMonths, isNot(contains('Month 10')));
    });

    testWidgets('shows an info message once at the 10-file limit',
        (tester) async {
      await openDialog(
        tester,
        availableMonths: elevenMonths,
        showCombineOption: true,
        isWebOverride: true,
      );
      await tester.tap(find.textContaining('Combine into'));
      await tester.pumpAndSettle();
      expect(find.textContaining('10-file'), findsOneWidget);
    });

    testWidgets('no cap or info message while combine stays on',
        (tester) async {
      await openDialog(
        tester,
        availableMonths: elevenMonths,
        showCombineOption: true,
        isWebOverride: true,
      );
      expect(find.textContaining('10-file'), findsNothing);
      expect(tileFor(tester, 'Month 10').onChanged, isNotNull);
    });

    testWidgets('no cap on non-web platforms even with combine off',
        (tester) async {
      await openDialog(
        tester,
        availableMonths: elevenMonths,
        showCombineOption: true,
        isWebOverride: false,
      );
      await tester.tap(find.textContaining('Combine into'));
      await tester.pumpAndSettle();

      final month10 = tileFor(tester, 'Month 10');
      expect(month10.value, isTrue);
      expect(month10.onChanged, isNotNull);
      expect(find.textContaining('10-file'), findsNothing);
    });

    testWidgets('no cap with 10 or fewer available months', (tester) async {
      final tenMonths = List.generate(10, (i) => 'Month $i');
      await openDialog(
        tester,
        availableMonths: tenMonths,
        showCombineOption: true,
        isWebOverride: true,
      );
      await tester.tap(find.textContaining('Combine into'));
      await tester.pumpAndSettle();

      expect(find.textContaining('10-file'), findsNothing);
      final month9 = tileFor(tester, 'Month 9');
      expect(month9.value, isTrue);
      expect(month9.onChanged, isNotNull);
    });
  });

  group('ExportMonthPickerDialog system nav bar clearance (bottom sheet)',
      () {
    // AppBreakpoints.isWide treats width >= 600 as wide (dialog, not bottom
    // sheet) — use a narrow phone-portrait viewport so show() actually picks
    // the bottom-sheet branch these tests target.
    testWidgets(
        'Export button stays above the system nav bar / gesture inset',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const navBarHeight = 48.0;
      await openDialog(
        tester,
        systemInsets: const EdgeInsets.only(bottom: navBarHeight),
      );

      final screenHeight = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final buttonBottom =
          tester.getBottomLeft(find.widgetWithText(ElevatedButton, 'Export'))
              .dy;

      expect(buttonBottom, lessThanOrEqualTo(screenHeight - navBarHeight));
    });
  });
}
