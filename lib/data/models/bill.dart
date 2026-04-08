import 'package:uuid/uuid.dart';

import './payment.dart';

/// Represents a single utility bill (electricity, gas, water, etc.) owed by
/// the household.
///
/// A [Bill] tracks the billing company, type, total amount, due date, payment
/// status, and how much has already been paid ([amountPaid]).  The [billId] is
/// a UUID assigned on creation and used as the stable foreign key across
/// payments and email records.
class Bill {
  final int? id;
  String billId;
  final String company;
  final double amount;
  final BillType type;
  final DateTime dueDate;
  double? amountPaid;
  PaymentStatus status;
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
    this.amountPaid,
  }) : billId = billId ?? Uuid().v4();

  /// Deserializes a [Bill] from a flat JSON map, as returned by the REST API
  /// or stored in the SQLite `bills` table (standard column names).
  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'],
      billId: json['billId'],
      company: json['company'],
      type: BillTypeExtension.fromString(json['type']),
      amount: (json['amount'] ?? 0).toDouble(),
      dueDate: DateTime.parse(json['dueDate']),
      status: PaymentStatusExtension.fromString(json['status']),
      notes: json['notes'],
      amountPaid: (json['amountPaid'] as num?)?.toDouble(),
    );
  }

  /// Deserializes a [Bill] from a row returned by a JOIN query in which bill
  /// columns are prefixed with `b_` (e.g. `b_id`, `b_billId`, `b_company`).
  ///
  /// Also tolerates pre-hydrated [BillType] / [PaymentStatus] enum values that
  /// may already be present when rows are assembled in Dart before JSON round-
  /// tripping.
  factory Bill.billFromJson(Map<String, dynamic> map) {
    final rawType = map['b_type'];
    final rawStatus = map['b_status'];

    final billType = rawType is BillType
        ? rawType
        : BillTypeExtension.fromString(rawType?.toString() ?? 'other');
    final paymentStatus = rawStatus is PaymentStatus
        ? rawStatus
        : PaymentStatusExtension.fromString(rawStatus?.toString() ?? 'unknown');

    return Bill(
      id: map['b_id'],
      billId: map['b_billId'],
      company: map['b_company'],
      type: billType,
      amount: (map['b_amount'] ?? 0).toDouble(),
      dueDate: DateTime.parse(map['b_dueDate']),
      status: paymentStatus,
      notes: map['b_notes'],
      amountPaid: (map['b_amountPaid'] as num?)?.toDouble(),
    );
  }

  /// Serializes this bill to a flat JSON map suitable for the REST API body
  /// or direct SQLite insertion.  The [dueDate] is encoded as `yyyy-MM-dd`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'billId': billId,
      'company': company,
      'type': type.name.toLowerCase(),
      'amount': amount,
      'dueDate': dueDate.toIso8601String().split('T').first,
      'status': status.name.toLowerCase(),
      'notes': notes,
      'amountPaid': amountPaid,
    };
  }

  /// Returns the canonical display name for the billing company derived from
  /// the [type] and [company] fields.  Falls back to the raw [company] string
  /// for [BillType.creditcard] variants and [BillType.other].
  String get companyName {
    switch (type) {
      case BillType.electric:
        return 'Alectra Utilities';
      case BillType.gas:
        if (company.toLowerCase().contains('enbridge')) {
          return 'Enbridge Gas';
        }
        return 'Crown Crest Capital';
      case BillType.internet:
        return 'Bell Canada';
      case BillType.water:
        return 'Region of Peel Water';
      case BillType.rent:
        return 'James & Joana Landlords';
      case BillType.phone:
        return 'Freedom Mobile';
      case BillType.creditcard:
        if (company.toLowerCase().contains('simplii')) {
          return 'Simplii Financial';
        } else if (company.toLowerCase().contains('neofinancial')) {
          return 'Neo Financial';
        } else if (company.toLowerCase().contains('rbc')) {
          return 'RBC Royal Bank';
        } else if (company.toLowerCase().contains('bmo')) {
          return 'BMO Bank of Montreal';
        }
        return company;
      case BillType.personallineofcredit:
        return 'Simplii Financial Personal Line of Credit';
      case BillType.other:
        return company; // Use the provided company name for "Other"
    }
  }
}

/// Categories of utility bills tracked by the app.
enum BillType {
  electric,
  gas,
  internet,
  water,
  rent,
  phone,
  creditcard,
  personallineofcredit,
  other,
}

/// Extension that adds a human-readable [name] getter and a [fromString]
/// factory to [BillType], enabling round-trip serialization with the database
/// and REST API.
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
      case BillType.phone:
        return 'Phone';
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
      case 'phone':
        return BillType.phone;
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
