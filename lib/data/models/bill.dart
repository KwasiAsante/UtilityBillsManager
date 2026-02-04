import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:uuid/uuid.dart';

class Bill {
  final int? id;
  String billId;
  final String company;
  final double amount;
  final BillType type;
  final String dueDate;
  final PaymentStatus status;
  final String? notes;

  Bill({
    this.id,
    String? billId,
    required this.company,
    required this.type,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.notes,
  }) : billId = billId ?? Uuid().v4();

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'],
      billId: json['billId'],
      company: json['company'],
      type: BillTypeExtension.fromString(json['type']),
      amount: (json['amount'] ?? 0).toDouble(),
      dueDate: json['dueDate'],
      status: PaymentStatusExtension.fromString(json['status']),
      notes: json['notes']
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'billId': billId,
      'company': company,
      'type': type.name.toLowerCase(),
      'amount': amount,
      'dueDate': dueDate,
      'status': status.name.toLowerCase(),
      'notes': notes
    };
  }
}

enum BillType {
  electric,
  gas,
  internet,
  water,
  rent,
  creditcard,
  personallineofcredit,
  other,
}

extension BillTypeExtension on BillType {
  String get name {
    switch (this) {
      case BillType.electric:
        return 'Electric';
      case BillType.gas:
        return 'Gas';
      case BillType.internet:
        return 'Internet';
      case BillType.water:
        return 'Water';
      case BillType.rent:
        return 'Rent';
      case BillType.creditcard:
        return 'Credit Card';
      case BillType.personallineofcredit:
        return 'Personal Line of Credit';
      case BillType.other:
        return 'Other';
    }
  }

  static BillType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'electric':
        return BillType.electric;
      case 'gas':
        return BillType.gas;
      case 'internet':
        return BillType.internet;
      case 'water':
        return BillType.water;
      case 'rent':
        return BillType.rent;
      case 'creditcard':
      case 'credit card':
        return BillType.creditcard;
      case 'personallineofcredit':
      case 'personal line of credit':
        return BillType.personallineofcredit;
      default:
        return BillType.other;
    }
  }
}
