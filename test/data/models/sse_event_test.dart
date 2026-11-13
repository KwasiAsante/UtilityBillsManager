import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/sse_event.dart';

void main() {
  group('parseSseEventType', () {
    test('parses every type the server sends', () {
      expect(parseSseEventType('newBill'), SseEventType.newBill);
      expect(parseSseEventType('newPayment'), SseEventType.newPayment);
      expect(
        parseSseEventType('billSummaryReminder'),
        SseEventType.billSummaryReminder,
      );
    });

    test('recognises every SseEventType by name', () {
      for (final type in SseEventType.values) {
        expect(parseSseEventType(type.name), type);
      }
    });

    test('returns null for unknown or missing types', () {
      expect(parseSseEventType('somethingElse'), isNull);
      expect(parseSseEventType(''), isNull);
      expect(parseSseEventType(null), isNull);
    });
  });
}
