import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:utility_bills_manager/screens/auth/login_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen() => const MaterialApp(home: LoginScreen());

  group('LoginScreen layout', () {
    testWidgets('shows email and password fields', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    });

    testWidgets('shows Sign in and Create account buttons', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      // Heading + button both show 'Sign in'
      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('Create account'), findsOneWidget);
    });
  });

  group('LoginScreen validation', () {
    testWidgets('shows validation errors when submitting empty form', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      // FilledButton is the last 'Sign in' widget (heading is first)
      await tester.tap(find.text('Sign in').last);
      await tester.pumpAndSettle();
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });
  });

  group('LoginScreen navigation', () {
    testWidgets('Create account navigates to RegisterScreen', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      // The sign-in link only exists on RegisterScreen
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Sign in'),
        ),
        findsOneWidget,
      );
    });
  });
}
