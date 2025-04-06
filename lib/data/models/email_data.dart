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
    this.billId,
    required this.processed,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'emailSubject': emailSubject,
      'emailBody': emailBody,
      'billId': billId,
      'processed': processed ? 1 : 0,
    };
  }

  factory EmailData.fromMap(Map<String, dynamic> map) {
    return EmailData(
      id: map['id'],
      emailSubject: map['emailSubject'],
      emailBody: map['emailBody'],
      billId: map['billId'],
      processed: map['processed'] == 1,
    );
  }
}
