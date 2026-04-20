import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/dialogs/sync_options_dialog.dart';

void main() {
  late Future<SyncOptions?> dialogFuture;

  Widget buildApp() {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () {
              dialogFuture = SyncOptionsDialog.show(context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('SyncOptionsDialog initial state', () {
    testWidgets('shows From chip with Any date placeholder', (tester) async {
      await openDialog(tester);
      expect(find.text('Any date'), findsOneWidget);
    });

    testWidgets('shows To chip with No end date placeholder', (tester) async {
      await openDialog(tester);
      expect(find.text('No end date'), findsOneWidget);
    });
  });

  group('SyncOptionsDialog To chip disabled state', () {
    testWidgets('To chip does not open date picker when From is not set',
        (tester) async {
      await openDialog(tester);
      // The To chip is behind IgnorePointer; the tap is intentionally expected to miss.
      await tester.tap(find.text('No end date'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsNothing);
    });
  });

  group('SyncOptionsDialog From date selection', () {
    testWidgets(
        'tapping From chip opens date picker and accepting updates label',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Any date'));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Any date'), findsNothing);
    });
  });

  group('SyncOptionsDialog To chip enabled after From set', () {
    testWidgets('To chip opens date picker after From is set', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Any date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No end date'));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('No end date'), findsNothing);
    });
  });

  group('SyncOptionsDialog clearing', () {
    testWidgets('clearing From also clears To', (tester) async {
      await openDialog(tester);
      // Set From
      await tester.tap(find.text('Any date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Set To
      await tester.tap(find.text('No end date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Clear From (first clear icon)
      await tester.tap(find.byIcon(Icons.clear).first);
      await tester.pumpAndSettle();
      expect(find.text('Any date'), findsOneWidget);
      expect(find.text('No end date'), findsOneWidget);
    });
  });

  group('SyncOptionsDialog Fetch last 50', () {
    testWidgets('checking Fetch last 50 hides the date range row',
        (tester) async {
      await openDialog(tester);
      expect(find.text('Any date'), findsOneWidget);
      await tester.tap(find.text('Fetch last 50 emails instead'));
      await tester.pumpAndSettle();
      expect(find.text('Any date'), findsNothing);
      expect(find.text('No end date'), findsNothing);
    });
  });

  group('SyncOptionsDialog return values', () {
    testWidgets('Sync with no dates returns SyncOptions with all nulls',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result, isNotNull);
      expect(result!.earliestDate, isNull);
      expect(result.latestDate, isNull);
      expect(result.maxEmails, isNull);
    });

    testWidgets('Fetch last 50 returns SyncOptions with maxEmails 50',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Fetch last 50 emails instead'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result!.maxEmails, equals(50));
      expect(result.earliestDate, isNull);
      expect(result.latestDate, isNull);
    });

    testWidgets('Cancel returns null', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result, isNull);
    });

    testWidgets('Sync with both dates returns SyncOptions with both dates set',
        (tester) async {
      await openDialog(tester);
      // Set From
      await tester.tap(find.text('Any date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Set To
      await tester.tap(find.text('No end date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Sync
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      final result = await dialogFuture;
      expect(result!.earliestDate, isNotNull);
      expect(result.latestDate, isNotNull);
      expect(result.maxEmails, isNull);
    });
  });
}
