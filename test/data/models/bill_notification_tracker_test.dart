import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill_notification_tracker.dart';

void main() {
  group('BillNotificationTracker', () {
    test('toJson omits id', () {
      final t = BillNotificationTracker(
        id: 1,
        rentorId: 'r1',
        billId: 'b1',
        billType: 'electric',
        month: 4,
        year: 2026,
        receivedAt: '2026-04-01T10:00:00.000',
      );
      final json = t.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['rentorId'], equals('r1'));
      expect(json['billId'], equals('b1'));
      expect(json['billType'], equals('electric'));
      expect(json['month'], equals(4));
      expect(json['year'], equals(2026));
      expect(json['receivedAt'], equals('2026-04-01T10:00:00.000'));
    });

    test('fromJson round-trips', () {
      final map = {
        'id': 5,
        'rentorId': 'r1',
        'billId': 'b2',
        'billType': 'gas',
        'month': 4,
        'year': 2026,
        'receivedAt': '2026-04-02T08:00:00.000',
      };
      final t = BillNotificationTracker.fromJson(map);
      expect(t.id, equals(5));
      expect(t.rentorId, equals('r1'));
      expect(t.billId, equals('b2'));
      expect(t.billType, equals('gas'));
      expect(t.month, equals(4));
      expect(t.year, equals(2026));
      expect(t.receivedAt, equals('2026-04-02T08:00:00.000'));
    });
  });
}
