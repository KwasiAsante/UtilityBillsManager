import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:uuid/uuid.dart';

class Payment {
  final int? id;
  final String? paymentId;
  List<String>? billIds;
  String? rentorId;
  final double amountPaid;
  final String? paymentDate;
  List<Bill>? bills;
  final Rentor? rentor;

  Payment({
    this.id,
    String? paymentId,
    this.billIds,
    this.rentorId,
    required this.amountPaid,
    required this.paymentDate,
    this.bills,
    this.rentor
  }): paymentId = paymentId ?? Uuid().v4();

  void addBill(Bill newBill) {
    if (newBill.billId.isNotEmpty) {
      billIds ??= [];
      bills ??= [];

      if (!billIds!.contains(newBill.billId)) {
        billIds!.add(newBill.billId);
      }

      if (bills != null && !bills!.any((bl) => bl.billId == newBill.billId)) {
        bills!.add(newBill);
      }
    }
  }

  void removeBill(String billId) {
    if (bills != null) {
      bills!.removeWhere((bill) => bill.billId == billId);
    }

    if (billIds != null) {
      billIds!.removeWhere((id) => id == billId);
    }
  }

  set rentor(Rentor? newRentor) {
    if (newRentor != null && ((rentorId == null || rentorId!.isEmpty) || newRentor.rentorId == rentorId)) {
      rentor = newRentor;
      rentorId = newRentor.rentorId;
    }
  }

  String billNames({bool newLine = false}) {
    if (bills != null && bills!.isNotEmpty) {
      return bills!.map((b) => '${b.type.name}: ${b.companyName} - ${b.dueDate}').join(newLine ? '\n' : ', ');
    } else {
      return 'Unknown Bills';
    }
  }

  String get rentorName {
    if (rentor != null) {
      return rentor!.name;
    } else {
      return 'Unknown Rentor';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'paymentId': paymentId,
      'rentorId': (rentorId == null || rentorId!.trim().isEmpty) ? null : rentorId,
      'amountPaid': amountPaid,
      'paymentDate': paymentDate,
    };
  }

  factory Payment.fromJson(Map<String, dynamic> map, {List<Map<String, dynamic>>? billRows}) {
    final dynamic rawPaymentId = map['paymentId'];
    final dynamic rawRentorId = map['rentorId'];

    final dynamic rawBillIds = map['billIds'];
    List<String> billIds = [];
    if (rawBillIds != null && rawBillIds is List) {
      billIds = List<String>.from(rawBillIds);
    }

    final List<Bill> parsedBills = [];
    // Parse bill rows passed from payment_bills/bills join (b_ prefixed columns).
    if (billRows != null && billRows.isNotEmpty) {
      for (final billRow in billRows) {
        if (billRow['b_id'] != null) {
          parsedBills.add(Bill.billFromJson(billRow));
        }
      }
    } else if (map['b_id'] != null) {
      // Backward-compatible path when a single joined row is passed directly.
      parsedBills.add(Bill.billFromJson(map));
    }

    Rentor? rentor;
    if (map['r_id'] != null) {
      rentor = Rentor.rentorFromJson(map);
    }

    if (billIds.isEmpty && parsedBills.isNotEmpty) {
      billIds = parsedBills.map((b) => b.billId).toList();
    }

    return Payment(
      id: map['id'],
      paymentId: rawPaymentId?.toString(),
      billIds: billIds.isEmpty ? null : billIds,
      rentorId: rawRentorId?.toString(),
      amountPaid: (map['amountPaid'] as num).toDouble(),
      paymentDate: map['paymentDate'],
      bills: parsedBills.isEmpty ? null : parsedBills,
      rentor: rentor,
    );
  }

  factory Payment.paymentFromJson(Map<String, dynamic> map) {
    final dynamic rawPaymentId = map['p_paymentId'];
    final dynamic rawBillIds = map['p_billIds'];

    List<String> billIds = [];
    if (rawBillIds != null && rawBillIds.toString().isNotEmpty) {
      billIds = rawBillIds.toString().split(',');
    }

    return Payment(
      id: map['p_id'],
      paymentId: rawPaymentId?.toString(),
      billIds: billIds,
      rentorId: map['p_rentorId'],
      amountPaid: (map['p_amountPaid'] as num).toDouble(),
      paymentDate: map['p_paymentDate'],
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