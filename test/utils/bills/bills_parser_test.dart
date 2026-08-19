import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/utils/bills/bills_parser.dart';

void main() {
  group('BillsParser.extractAmount', () {
    test('parses a positive dollar amount', () {
      expect(BillsParser.extractAmount('Total: \$360.00'), 360.00);
    });

    test('parses a negative amount with a leading dollar sign', () {
      expect(BillsParser.extractAmount('Total: -\$360.00'), -360.00);
    });

    test('parses a bare negative amount with no dollar sign', () {
      expect(BillsParser.extractAmount('Total: -360.00'), -360.00);
    });
  });

  group('BillsParser.extractSmartAmount', () {
    group('negative / credit amounts', () {
      test('handles a bare negative amount on a "total due" line', () {
        const text = 'total due: -360.00';
        expect(BillsParser.extractSmartAmount(text), -360.0);
      });

      test('handles a negative amount with a leading dollar sign', () {
        const text = 'total due: -\$360.00';
        expect(BillsParser.extractSmartAmount(text), -360.0);
      });

      test('handles a negative amount on the line after the keyword', () {
        const text = 'total due\n-\$45.00\nother stuff';
        expect(BillsParser.extractSmartAmount(text), -45.0);
      });

      test('handles a negative amount in the dollar-sign fallback', () {
        const text = 'Your account shows a credit of -\$360.00.';
        expect(BillsParser.extractSmartAmount(text), -360.0);
      });

      test('does not treat a positive amount as negative', () {
        const text = 'total due: \$150.00';
        expect(BillsParser.extractSmartAmount(text), 150.0);
      });
    });
  });

  group('BillsParser.inferStatus', () {
    test('flags a negative amount as unknown rather than paid', () {
      expect(BillsParser.inferStatus(-360.44), PaymentStatus.unknown);
    });

    test('treats a zero balance as paid', () {
      expect(BillsParser.inferStatus(0.0), PaymentStatus.paid);
    });

    test('treats a positive amount as unpaid', () {
      expect(BillsParser.inferStatus(150.0), PaymentStatus.unpaid);
    });
  });

  group('BillsParser.getAmountFromNextIndex', () {
    final pattern = RegExp(r'(?:\$\s?)?(\d{1,5}(?:[.,]\d{2})?)\b');

    test('returns a negative amount when the line has a leading "-"', () {
      final lines = ['keyword line', '-\$42.00', 'other'];
      expect(BillsParser.getAmountFromNextIndex(pattern, 0, lines), -42.0);
    });

    test('returns a negative bare amount two lines after index', () {
      final lines = ['keyword', 'nothing here', '-33.00'];
      expect(BillsParser.getAmountFromNextIndex(pattern, 0, lines), -33.0);
    });
  });
}
