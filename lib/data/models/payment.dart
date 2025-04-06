class Payment {
  final int? id;
  final int billId;
  final int rentorId;
  final double amountPaid;
  final String paymentDate;

  Payment({
    this.id,
    required this.billId,
    required this.rentorId,
    required this.amountPaid,
    required this.paymentDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'billId': billId,
      'rentorId': rentorId,
      'amountPaid': amountPaid,
      'paymentDate': paymentDate,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'],
      billId: map['billId'],
      rentorId: map['rentorId'],
      amountPaid: map['amountPaid'],
      paymentDate: map['paymentDate'],
    );
  }
}
