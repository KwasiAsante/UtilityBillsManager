import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/utils/payments/payments_parser.dart';

void main() {
  group('PaymentsParser.extractAmount', () {
    test('parses a positive dollar amount', () {
      expect(PaymentsParser.extractAmount('Total: \$360.00'), 360.00);
    });

    test('parses a negative amount with a leading dollar sign', () {
      expect(PaymentsParser.extractAmount('Total: -\$360.00'), -360.00);
    });

    test('parses a bare negative amount with no dollar sign', () {
      expect(PaymentsParser.extractAmount('Total: -360.00'), -360.00);
    });
  });

  group('PaymentsParser.extractSmartAmount', () {
    group('negative / credit amounts', () {
      test('handles a bare negative amount on a "total due" line', () {
        const text = 'total due: -360.00';
        expect(PaymentsParser.extractSmartAmount(text), -360.0);
      });

      test('handles a negative amount with a leading dollar sign', () {
        const text = 'total due: -\$360.00';
        expect(PaymentsParser.extractSmartAmount(text), -360.0);
      });

      test('handles a negative amount in the dollar-sign fallback', () {
        const text = 'Your account shows a credit of -\$360.00.';
        expect(PaymentsParser.extractSmartAmount(text), -360.0);
      });

      test('does not treat a positive amount as negative', () {
        const text = 'total due: \$150.00';
        expect(PaymentsParser.extractSmartAmount(text), 150.0);
      });
    });
  });

  group('PaymentsParser.getAmountFromNextIndex', () {
    final pattern = RegExp(r'(?:\$\s?)?(\d{1,5}(?:[.,]\d{2})?)\b');

    test('returns a negative amount when the line has a leading "-"', () {
      final lines = ['keyword line', '-\$42.00', 'other'];
      expect(PaymentsParser.getAmountFromNextIndex(pattern, 0, lines), -42.0);
    });
  });
}
