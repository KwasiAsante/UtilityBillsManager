import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/helpers/payments/payments_helper.dart';
import 'package:uuid/uuid.dart';

class Rentor {
  final int? id;
  final String rentorId;
  final String name;
  final String? email;
  final String? phone;
  final double defaultPercentage;
  final Map<BillType, double> billPercentages; // e.g., {'Electric': 0.1, 'Gas': 0.2}
  final List<BillType> excludedBillTypes;
  String? lastPaymentDate;

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
      lastPaymentDate: json['lastPaymentDate'],
    );
  }

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
      lastPaymentDate: map['r_lastPaymentDate'],
    );
  }

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
      'lastPaymentDate': lastPaymentDate,
    };
  }

  Map<String, dynamic> toDbJson() {
    final payload = Map<String, dynamic>.from(toJson());
    payload['billPercentages'] = jsonEncode(payload['billPercentages']);
    payload['excludedBillTypes'] = jsonEncode(payload['excludedBillTypes']);
    return payload;
  }

  DateTime? get lastPaymentDateTime {
    if (lastPaymentDate != null) {
      try {
        return DateTime.parse(lastPaymentDate!);
      } catch (e) {
        // Handle parsing error if needed
        return null;
      }
    }
    return null;
  }

  static double calculateOwedAmount(Rentor rentor, Bill bill) {
    double? customPercentage = rentor.billPercentages[bill.type];
    double percentage = customPercentage ?? 0.0;
    return (bill.amount * (percentage / 100)).round().toDouble();
  }

  static double calculateTotalOwed(Rentor rentor, List<Bill> bills) {
    double total = 0;
    for (var bill in bills) {
      total += calculateOwedAmount(rentor, bill);
    }
    return total;
  }

  double owedAmount(Bill bill) {
    return calculateOwedAmount(this, bill);
  }

  double totalOwed(List<Bill> bills) {
    return calculateTotalOwed(this, bills);
  }

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

    int compareNullable<T extends Comparable<T>>(
        T? a,
        T? b, {
          bool descending = false,
        }) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;

      final comparison = a.compareTo(b);
      return descending ? -comparison : comparison;
    }

    payments.sort((a, b) => compareNullable(b.paymentDateTime, a.paymentDateTime, descending: true));

    if (compareNullable(payments.first.paymentDateTime, lastPaymentDateTime, descending: true) >= 0) {
      if (kDebugMode) {
        print('No update needed for Rentor $rentorId - existing lastPaymentDate is more recent or equal to latest payment');
      }
      return;
    }

    lastPaymentDate = payments.first.paymentDate;
  }
}

extension RentorExtensions on Rentor {
  double getAmountOwed(List<Bill> bills) {
    return bills.fold(0.0, (total, bill) {
      final percent = billPercentages[bill.type] ?? 0.0;
      return total + (bill.amount * percent);
    });
  }
}