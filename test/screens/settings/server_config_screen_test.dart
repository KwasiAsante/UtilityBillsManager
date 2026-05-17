import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:utility_bills_manager/screens/settings/server_config_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(fileInput: '');
  });

  Widget buildScreen() {
    return const MaterialApp(home: ServerConfigScreen());
  }

  group('ServerConfigScreen section labels', () {
    testWidgets('shows Manual Sync section label', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Manual Sync'), findsOneWidget);
    });

    testWidgets('shows Background Sync section label', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Background Sync'), findsOneWidget);
    });

    testWidgets('does not show old Sync Settings label', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Sync Settings'), findsNothing);
    });
  });

  group('ServerConfigScreen helper text', () {
    testWidgets('shows helper text for Default Earliest Email Date', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The default start date used when you trigger a manual sync. '
          'You can override this each time in the sync dialog.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows helper text for Sync Delay', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'How long to wait after the app starts before the first background sync runs.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows helper text for Sync Interval', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'How often the app checks for new emails in the background. '
          '900 = every 15 minutes.',
        ),
        findsOneWidget,
      );
    });
  });
}
