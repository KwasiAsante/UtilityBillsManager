import 'dart:math';

class EmailData {
  final int? id;
  final String emailSubject;
  final String emailBody;
  final int? billId;
  final bool processed;

  EmailData({
    this.id,
    required this.emailSubject,
    required this.emailBody,
    int? billId,
    required this.processed,
  }) : billId = billId ?? _generateBillId();

  static int _generateBillId() {
    final random = Random();
    // Get current timestamp in seconds
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Generate a random 4-digit number
    final randomPart = random.nextInt(9000) + 1000;
    // Combine timestamp and random number to create a unique ID
    return int.parse('$timestamp$randomPart');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'emailSubject': emailSubject,
      'emailBody': emailBody,
      'billId': billId,
      'processed': processed ? 1 : 0,
    };
  }

  factory EmailData.fromJson(Map<String, dynamic> map) {
    return EmailData(
      id: map['id'],
      emailSubject: map['emailSubject'],
      emailBody: map['emailBody'],
      billId: map['billId'],
      processed: map['processed'] == 1,
    );
  }
} 