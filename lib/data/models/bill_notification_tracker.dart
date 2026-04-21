/// A record tracking that a specific bill notification has been received for
/// a specific rentor. Persisted in the `bill_notification_tracker` SQLite table.
class BillNotificationTracker {
  final int? id;
  final String rentorId;
  final String billId;
  final String billType;
  final int month;
  final int year;
  final String receivedAt; // ISO-8601 string

  const BillNotificationTracker({
    this.id,
    required this.rentorId,
    required this.billId,
    required this.billType,
    required this.month,
    required this.year,
    required this.receivedAt,
  });

  /// Serialises for SQLite insertion. Does NOT include [id].
  Map<String, dynamic> toJson() => {
        'rentorId': rentorId,
        'billId': billId,
        'billType': billType,
        'month': month,
        'year': year,
        'receivedAt': receivedAt,
      };

  factory BillNotificationTracker.fromJson(Map<String, dynamic> map) =>
      BillNotificationTracker(
        id: map['id'] as int?,
        rentorId: map['rentorId'] as String,
        billId: map['billId'] as String,
        billType: map['billType'] as String,
        month: map['month'] as int,
        year: map['year'] as int,
        receivedAt: map['receivedAt'] as String,
      );
}
