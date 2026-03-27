import 'dart:convert';

import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:uuid/uuid.dart';

class Rentor {
  final int? id;
  final String rentorId;
  final String name;
  final String? email;
  final String? phone;
  final double defaultPercentage;
  final Map<BillType, double> billPercentages; // e.g., {'Electric': 0.1, 'Gas': 0.2}
  double? amountPaid;
  String? lastPaymentDate;

  Rentor({
    this.id,
    String? rentorId,
    required this.name,
    this.email,
    this.phone,
    required this.defaultPercentage,
    required this.billPercentages,
    this.amountPaid,
    this.lastPaymentDate,
  }) : rentorId = rentorId ?? Uuid().v4();

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
      billPercentages: parsedMap
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
      'billPercentages': encodedMap
    };
  }

  Map<String, dynamic> toDbJson() {
    final payload = Map<String, dynamic>.from(toJson());
    payload['billPercentages'] = jsonEncode(payload['billPercentages']);
    return payload;
  }

  static double calculateOwedAmount(Rentor rentor, Bill bill) {
    double? customPercentage = rentor.billPercentages[bill.type];
    double percentage = customPercentage ?? rentor.defaultPercentage;
    return bill.amount * percentage;
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
}

extension RentorExtensions on Rentor {
  double getAmountOwed(List<Bill> bills) {
    return bills.fold(0.0, (total, bill) {
      final percent = billPercentages[bill.type] ?? defaultPercentage;
      return total + (bill.amount * percent);
    });
  }
}