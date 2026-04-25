import 'dart:math';

import 'package:uuid/uuid.dart';

import './bill.dart';
import './payment.dart';

/// Stores the raw content of an email fetched from the mailbox, along with
/// references to any [Bill] or [Payment] that was parsed from it.
///
/// The [processed] flag indicates whether the email has been analysed and its
/// bill/payment data saved to the database.  An [emailId] is derived from the
/// email's metadata (sender + date + subject hash) to avoid duplicate imports.
class EmailData {
  final int? id;
  final String emailDataId;
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

  /// Serializes this [EmailData] to a flat JSON map for SQLite / REST API.
  /// [processed] is stored as an integer (1 = true, 0 = false) because SQLite
  /// has no native boolean type.
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

  /// Deserializes an [EmailData] from a flat JSON map.
  ///
  /// If the map contains `b_id` (bill JOIN columns) or `p_id` (payment JOIN
  /// columns) they are hydrated into the [bill] / [payment] fields
  /// automatically using [Bill.billFromJson] and [Payment.paymentFromJson].
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

  /// Generates a pseudo-unique numeric email ID by combining the current Unix
  /// timestamp (seconds) with a random 4-digit suffix.  Used as a fallback
  /// when the email has no server-assigned ID.
  static int _generateEmailId() {
    final random = Random();
    // Get current timestamp in seconds
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Generate a random 4-digit number
    final randomPart = random.nextInt(9000) + 1000;
    // Combine timestamp and random number to create a unique ID
    return int.parse('$timestamp$randomPart');
  }

  /// Returns [emailId] as a string, lazily generating one via [_generateEmailId]
  /// if the field is not yet set.
  String getEmailId() {
    emailId ??= _generateEmailId();
    return emailId.toString();
  }
}
