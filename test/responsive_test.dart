import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/app_breakpoints.dart';
import 'package:utility_bills_manager/widgets/responsive_constraint.dart';

void main() {
  group('AppBreakpoints', () {
    testWidgets('isWide returns false when width < 600', (tester) async {
      tester.view.physicalSize = const Size(599, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = AppBreakpoints.isWide(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, isFalse);
    });

    testWidgets('isWide returns true when width >= 600', (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = AppBreakpoints.isWide(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, isTrue);
    });
  });

  group('ResponsiveConstraint', () {
    testWidgets('passes child through on compact', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveConstraint(
              child: SizedBox(key: Key('inner'), width: 500, height: 100),
            ),
          ),
        ),
      );
      // On compact, no Align wrapping — child renders directly
      expect(find.byKey(const Key('inner')), findsOneWidget);
      expect(find.byType(Align), findsNothing);
    });

    testWidgets('wraps child in Align and ConstrainedBox on wide', (tester) async {
      tester.view.physicalSize = const Size(800, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveConstraint(
              child: SizedBox(key: Key('inner'), width: 500, height: 100),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('inner')), findsOneWidget);
      expect(find.byType(Align), findsOneWidget);
      // Our ConstrainedBox is the one that constrains to maxWidth
      final constrainedBoxes = find.byType(ConstrainedBox);
      expect(constrainedBoxes, findsWidgets);
      // The last ConstrainedBox found should be ours (with maxWidth constraint)
      expect(tester.widget<ConstrainedBox>(constrainedBoxes.last).constraints.maxWidth, 720);
    });
  });
}
