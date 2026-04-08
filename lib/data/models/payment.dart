import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import './bill.dart';
import './rentor.dart';

/// Represents a single payment made by a rentor (or the household itself)
/// toward one or more [Bill]s.
///
/// Each [Payment] carries:
/// - [amountPaid] — the monetary amount of this transaction.
/// - [paymentDate] — when the payment was made.
/// - [billIds] / [bills] — the bills this payment contributes to.
/// - [rentorId] / [rentor] — the rentor who made the payment, if applicable.
///
/// The many-to-many relationship with bills is stored in the `payment_bills`
/// junction table; [billIds] is the in-memory projection of those rows.
class Payment {
  final int? id;
  final String? paymentId;
  List<String>? billIds;
  String? rentorId;
  final double amountPaid;
  final DateTime paymentDate;
  List<Bill>? bills;
  Rentor? rentor;

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

  /// Attaches [newBill] to this payment by adding its ID to [billIds] and the
  /// object to [bills].  Duplicate bills (same [billId]) are silently ignored.
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

  /// Removes the bill with [billId] from both [bills] and [billIds].
  void removeBill(String billId) {
    if (bills != null) {
      bills!.removeWhere((bill) => bill.billId == billId);
    }

    if (billIds != null) {
      billIds!.removeWhere((id) => id == billId);
    }
  }

  /// Assigns [newRentor] to this payment.  The assignment is skipped if:
  /// - [newRentor] is null, or
  /// - the payment already has a different rentor ID assigned.
  void addRentor(Rentor? newRentor) {
    if (newRentor != null && ((rentorId == null || rentorId!.isEmpty) || newRentor.rentorId == rentorId)) {
      rentor = newRentor;
      rentorId = newRentor.rentorId;
    }
  }

  /// Returns a formatted string listing all linked bill names.
  ///
  /// Each entry is formatted as `"<Type>: <CompanyName> - <yyyy-MM-dd>"`.
  /// When [newLine] is `true` entries are separated by `\n`; otherwise by `, `.
  /// Falls back to `"Unknown Bills"` if [bills] is empty.
  String billNames({bool newLine = false}) {
    if (bills != null && bills!.isNotEmpty) {
      return bills!.map((b) => '${b.type.name}: ${b.companyName} - ${DateFormat('yyyy-MM-dd').format(b.dueDate)}').join(newLine ? '\n' : ', ');
    } else {
      return 'Unknown Bills';
    }
  }

  /// Returns the rentor's display name, or `"Unknown Rentor"` if no rentor is
  /// associated with this payment.
  String get rentorName {
    if (rentor != null) {
      return rentor!.name;
    } else {
      return 'Unknown Rentor';
    }
  }

  /// Serializes this payment to a flat JSON map for the REST API or SQLite.
  /// Note: [bills] and [rentor] objects are **not** included — only their IDs.
  /// The [paymentDate] is encoded as `yyyy-MM-dd`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'paymentId': paymentId,
      'rentorId': (rentorId == null || rentorId!.trim().isEmpty) ? null : rentorId,
      'amountPaid': amountPaid,
      'paymentDate': paymentDate.toIso8601String().split('T').first,
    };
  }

  /// Deserializes a [Payment] from a flat JSON map (API response or SQLite row).
  ///
  /// Optionally accepts [billRows] — a list of `b_`-prefixed JOIN rows used to
  /// hydrate the [bills] list in a single pass, avoiding a second query.
  /// If [billRows] is omitted but the map itself contains `b_id`, a single
  /// bill is parsed from the map directly (backward-compatible path).
  /// A linked [Rentor] is parsed when `r_id` is present in the map.
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
      paymentDate: DateTime.parse(map['paymentDate']),
      bills: parsedBills.isEmpty ? null : parsedBills,
      rentor: rentor,
    );
  }

  /// Deserializes a [Payment] from a `p_`-prefixed JOIN query row.
  ///
  /// Used when payments are returned as part of a larger JOIN result (e.g.
  /// inside an [EmailData] query) where payment columns are aliased with
  /// the `p_` prefix.  Bill IDs are stored as a comma-separated string in
  /// `p_billIds` and split here.
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
      paymentDate: DateTime.parse(map['p_paymentDate']),
    );
  }
}

/// Payment state of a [Bill].
enum PaymentStatus {
  paid,
  unpaid,
  partial,
  unknown
}

/// Extension that adds display-name helpers and [fromString] parsing to
/// [PaymentStatus] for use in the UI and database serialization.
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