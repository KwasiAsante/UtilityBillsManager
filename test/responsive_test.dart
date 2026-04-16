import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/app_breakpoints.dart';

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
}
