import 'dart:math';

import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:uuid/uuid.dart';

class EmailData {
  final int? id;
  final String? emailDataId;
  final String emailSubject;
  final String emailBody;
  int? emailId;
  String? billId;
  String? paymentId;
  final bool processed;
  Bill? bill;
  Payment? payment;

  EmailData({
    this.id,
    String? emailDataId,
    required this.emailSubject,
    required this.emailBody,
    this.emailId,
    this.billId,
    this.paymentId,
    required this.processed,
    this.bill,
    this.payment
  }): emailDataId = emailDataId ?? Uuid().v4();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'emailDataId': emailDataId,
      'emailSubject': emailSubject,
      'emailBody': emailBody,
      'emailId': emailId,
      'billId': billId,
      'paymentId': paymentId,
      'processed': processed ? 1 : 0,
    };
  }

  factory EmailData.fromJson(Map<String, dynamic> map) {
    final dynamic rawEmailDataId = map['emailDataId'];
    final dynamic rawBillId = map['billId'];
    final dynamic rawPaymentId = map['paymentId'];
    final Bill? bill = (map['b_id'] != null) ? Bill.billFromJson(map) : null;
    final Payment? payment = (map['p_id'] != null) ? Payment.paymentFromJson(map) : null;
    return EmailData(
      id: map['id'],
      emailDataId: rawEmailDataId?.toString(),
      emailSubject: map['emailSubject'],
      emailBody: map['emailBody'],
      emailId: map['emailId'],
      billId: rawBillId?.toString(),
      paymentId: rawPaymentId?.toString(),
      processed: map['processed'] == 1,
      bill: bill,
      payment: payment
    );
  }

  static int _generateEmailId() {
    final random = Random();
    // Get current timestamp in seconds
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Generate a random 4-digit number
    final randomPart = random.nextInt(9000) + 1000;
    // Combine timestamp and random number to create a unique ID
    return int.parse('$timestamp$randomPart');
  }

  String getEmailId() {
    emailId ??= _generateEmailId();
    return emailId.toString();
  }
}
