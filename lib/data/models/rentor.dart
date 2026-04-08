import 'dart:convert';

import 'package:uuid/uuid.dart';

import './bill.dart';
import './payment.dart';
import '../../helpers/payments/payments_helper.dart';
import '../../utils/app_logger.dart';
import '../../utils/comparable_utils.dart';

/// Represents a tenant / rentor who contributes toward household utility bills.
///
/// Each rentor has:
/// - A [defaultPercentage] applied to all bills that don't have a specific
///   override in [billPercentages].
/// - A per-[BillType] override map ([billPercentages]) for fine-grained splits.
/// - An [excludedBillTypes] list for bill types the rentor never pays.
/// - A [lastPaymentDate] that is updated whenever a new [Payment] is recorded.
///
/// Amount calculations are available via [owedAmount], [totalOwed], and the
/// static helpers [calculateOwedAmount] / [calculateTotalOwed].
class Rentor {
  final int? id;
  final String rentorId;
  final String name;
  final String? email;
  final String? phone;
  final double defaultPercentage;
  final Map<BillType, double> billPercentages; // e.g., {'Electric': 0.1, 'Gas': 0.2}
  final List<BillType> excludedBillTypes;
  DateTime? lastPaymentDate;

  Rentor({
    this.id,
    String? rentorId,
    required this.name,
    this.email,
    this.phone,
    required this.defaultPercentage,
    required this.billPercentages,
    List<BillType>? excludedBillTypes,
    this.lastPaymentDate,
  })  : rentorId = rentorId ?? Uuid().v4(),
        excludedBillTypes = excludedBillTypes ?? const [];

  /// Parses the [excludedBillTypes] field from its stored form — either a
  /// JSON-encoded string (from SQLite) or a raw Dart [List] (from API JSON).
  /// Returns an empty list if [raw] is null or cannot be parsed.
  static List<BillType> _parseExcludedBillTypes(dynamic raw) {
    List<dynamic> list;
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      list = decoded is List ? decoded : [];
    } else if (raw is List) {
      list = raw;
    } else {
      return [];
    }
    return list.map((e) => BillTypeExtension.fromString(e.toString())).toList();
  }

  /// Deserializes a [Rentor] from a standard JSON map (API response or SQLite
  /// row with plain column names).
  ///
  /// The [billPercentages] field may arrive as a JSON-encoded string (SQLite)
  /// or as a nested [Map] (API).  Both forms are handled.
  factory Rentor.fromJson(Map<String, dynamic> json) {
    final rawBillPercentages = json['billPercentages'];
    final Map<String, dynamic> rawMap;

    if (rawBillPercentages is String && rawBillPercentages.isNotEmpty) {
      final decoded = jsonDecode(rawBillPercentages);
      rawMap = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
    } else if (rawBillPercentages is Map) {
      rawMap = rawBillPercentages.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } else {
      rawMap = <String, dynamic>{};
    }

    final parsedMap = rawMap.map(
      (key, value) =>
          MapEntry(BillTypeExtension.fromString(key), (value as num).toDouble()),
    );

    return Rentor(
      id: json['id'],
      rentorId: json['rentorId'] ?? (json['id'] != null ? 'legacy-${json['id']}' : null),
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      defaultPercentage: (json['defaultPercentage'] ?? 0).toDouble(),
      billPercentages: parsedMap,
      excludedBillTypes: _parseExcludedBillTypes(json['excludedBillTypes']),
      lastPaymentDate: json['lastPaymentDate'] != null
          ? DateTime.tryParse(json['lastPaymentDate'])
          : null,
    );
  }

  /// Deserializes a [Rentor] from a `r_`-prefixed JOIN query row (e.g. when a
  /// payment row is joined with its rentor).
  factory Rentor.rentorFromJson(Map<String, dynamic> map) {
    final rawBillPercentages = map['r_billPercentages'];
    final Map<String, dynamic> rawMap;

    if (rawBillPercentages is String && rawBillPercentages.isNotEmpty) {
      final decoded = jsonDecode(rawBillPercentages);
      rawMap = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
    } else if (rawBillPercentages is Map) {
      rawMap = rawBillPercentages.map(
            (key, value) => MapEntry(key.toString(), value),
      );
    } else {
      rawMap = <String, dynamic>{};
    }

    final parsedMap = rawMap.map(
          (key, value) =>
          MapEntry(BillTypeExtension.fromString(key), (value as num).toDouble()),
    );

    return Rentor(
      id: map['r_id'],
      rentorId: map['r_rentorId'] ?? (map['r_id'] != null ? 'legacy-${map['r_id']}' : null),
      name: map['r_name'],
      email: map['r_email'],
      phone: map['r_phone'],
      defaultPercentage: (map['r_defaultPercentage'] ?? 0).toDouble(),
      billPercentages: parsedMap,
      excludedBillTypes: _parseExcludedBillTypes(map['r_excludedBillTypes']),
      lastPaymentDate: map['r_lastPaymentDate'] != null
          ? DateTime.tryParse(map['r_lastPaymentDate'])
          : null,
    );
  }

  /// Serializes this rentor to a plain JSON map (suitable for the REST API).
  /// [billPercentages] keys are lowercased bill-type names; [excludedBillTypes]
  /// is a list of lowercased type name strings.
  Map<String, dynamic> toJson() {
    final encodedMap = billPercentages.map(
      (key, value) => MapEntry(key.name.toLowerCase(), value),
    );

    return {
      'id': id,
      'rentorId': rentorId,
      'name': name,
      'email': email,
      'phone': phone,
      'defaultPercentage': defaultPercentage,
      'billPercentages': encodedMap,
      'excludedBillTypes': excludedBillTypes.map((t) => t.name.toLowerCase()).toList(),
      'lastPaymentDate': lastPaymentDate?.toIso8601String().split('T').first,
    };
  }

  /// Serializes this rentor to a map suited for direct SQLite insertion.
  /// Unlike [toJson], the [billPercentages] and [excludedBillTypes] fields are
  /// JSON-encoded strings because SQLite stores them as TEXT columns.
  Map<String, dynamic> toDbJson() {
    final payload = Map<String, dynamic>.from(toJson());
    payload['billPercentages'] = jsonEncode(payload['billPercentages']);
    payload['excludedBillTypes'] = jsonEncode(payload['excludedBillTypes']);
    return payload;
  }

  /// Calculates the amount owed by [rentor] for a single [bill].
  ///
  /// Uses the bill-type-specific percentage from [rentor.billPercentages] if
  /// one exists; otherwise falls back to `0.0` (not the default percentage —
  /// that would override the user's explicit zero assignment).  The result is
  /// rounded to the nearest whole dollar.
  static double calculateOwedAmount(Rentor rentor, Bill bill) {
    double? customPercentage = rentor.billPercentages[bill.type];
    double percentage = customPercentage ?? 0.0;
    return (bill.amount * (percentage / 100)).round().toDouble();
  }

  /// Sums [calculateOwedAmount] across all [bills] for [rentor].
  static double calculateTotalOwed(Rentor rentor, List<Bill> bills) {
    double total = 0;
    for (var bill in bills) {
      total += calculateOwedAmount(rentor, bill);
    }
    return total;
  }

  /// Convenience instance wrapper for [calculateOwedAmount].
  double owedAmount(Bill bill) {
    return calculateOwedAmount(this, bill);
  }

  /// Convenience instance wrapper for [calculateTotalOwed].
  double totalOwed(List<Bill> bills) {
    return calculateTotalOwed(this, bills);
  }

  /// Updates [lastPaymentDate] to the most recent payment date in [payments].
  ///
  /// You can pass either fully hydrated [Payment] objects or just [paymentIds]
  /// (the method will fetch the corresponding payments from the database).
  /// The update is skipped when the existing [lastPaymentDate] is already
  /// more recent than or equal to the latest payment in the list.
  void updateLastPaymentDate({List<Payment>? payments, List<String>? paymentIds}) async {
    if (payments == null && paymentIds == null) {
      return;
    }

    if (payments == null) {
      final readResult = await PaymentsHelper().readAllPayments(paymentIds: paymentIds);
      if (readResult.isSuccess) {
        payments = readResult.data!;
      } else {
        return;
      }
    }

    if (payments.isEmpty) {
      return;
    }

    payments.sort((a, b) => ComparableUtils.compareNullable(a.paymentDate, b.paymentDate, descending: true));

    if (ComparableUtils.compareNullable(payments.first.paymentDate, lastPaymentDate, descending: true) >= 0) {
      AppLogger().d('No update needed for Rentor $rentorId - existing lastPaymentDate is more recent or equal to latest payment');
      return;
    }

    lastPaymentDate = payments.first.paymentDate;
  }
}

/// Additional computed helpers for [Rentor] that rely on bill fold operations.
extension RentorExtensions on Rentor {
  /// Returns the total amount owed by this rentor across all [bills], computed
  /// by summing [Rentor.calculateOwedAmount] for each bill via a fold.
  double getAmountOwed(List<Bill> bills) {
    return bills.fold(0.0, (total, bill) =>
      total + Rentor.calculateOwedAmount(this, bill));
  }
}