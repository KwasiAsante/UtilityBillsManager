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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'billId': billId,
      'rentorId': rentorId,
      'amountPaid': amountPaid,
      'paymentDate': paymentDate,
    };
  }

  factory Payment.fromJson(Map<String, dynamic> map) {
    return Payment(
      id: map['id'],
      billId: map['billId'],
      rentorId: map['rentorId'],
      amountPaid: map['amountPaid'],
      paymentDate: map['paymentDate'],
    );
  }
}

enum PaymentStatus {
  paid,
  unpaid,
  partial,
  unknown
}

extension PaymentStatusExtension on PaymentStatus {
  String get name {
    switch (this) {
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.unpaid:
        return 'Unpaid';
      case PaymentStatus.partial:
        return 'Partial';
      case PaymentStatus.unknown:
        return 'Unknown';
    }
  }

  static String getName(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.unpaid:
        return 'Unpaid';
      case PaymentStatus.partial:
        return 'Partial';
      case PaymentStatus.unknown:
        return 'Unknown';
    }
  }

  static PaymentStatus fromString(String type) {
    switch (type.toLowerCase()) {
      case 'paid':
        return PaymentStatus.paid;
      case 'unpaid':
        return PaymentStatus.unpaid;
      case 'partial':
        return PaymentStatus.partial;
      case 'unknown':
      default:
        return PaymentStatus.unknown;
    }
  }
}