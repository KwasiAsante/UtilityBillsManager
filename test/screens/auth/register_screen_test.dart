import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:utility_bills_manager/screens/auth/register_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen() => const MaterialApp(home: RegisterScreen());

  // Helper to find the "Sign in" RichText link
  Finder signInLink() => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('Sign in'));

  group('RegisterScreen layout', () {
    testWidgets('shows email and password fields', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    });

    testWidgets('shows Create account button', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      // The heading and the button both show "Create account"
      expect(find.text('Create account'), findsWidgets);
    });

    testWidgets('shows sign in link', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(signInLink(), findsOneWidget);
    });
  });

  group('RegisterScreen validation', () {
    testWidgets('shows error when submitting empty form', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      // Tap the FilledButton (last "Create account" widget)
      await tester.tap(find.text('Create account').last);
      await tester.pumpAndSettle();
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });
  });

  group('RegisterScreen navigation', () {
    testWidgets('Sign in link pops back', (tester) async {
      // Push RegisterScreen on top of a dummy screen so pop has somewhere to go
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => Navigator.push(
                ctx, MaterialPageRoute(builder: (_) => const RegisterScreen())),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(signInLink(), findsOneWidget);
      await tester.tap(signInLink());
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget); // back on the dummy screen
    });
  });
}
