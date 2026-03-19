import 'package:utility_bills_manager/data/models/bill.dart';

class Rentor {
  final int? id;
  final String name;
  final String? email;
  final String? phone;
  final double defaultPercentage;
  final Map<BillType, double> billPercentages; // e.g., {'Electric': 0.1, 'Gas': 0.2}
  final double? amountPaid;
  final String? lastPaymentDate;

  Rentor({
    this.id,
    required this.name,
    this.email,
    this.phone,
    required this.defaultPercentage,
    required this.billPercentages,
    this.amountPaid,
    this.lastPaymentDate,
  });

  factory Rentor.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> rawMap = json['billPercentages'] ?? {};
    Map<BillType, double> parsedMap = rawMap.map((key, value) =>
      MapEntry(BillTypeExtension.fromString(key), (value as num).toDouble())
    );

    return Rentor(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      defaultPercentage: (json['defaultPercentage'] ?? 0).toDouble(),
      billPercentages: parsedMap,
      amountPaid: json['amountPaid'],
      lastPaymentDate: json['lastPaymentDate'],
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, double> encodedMap = billPercentages.map((key, value) =>
      MapEntry(key.name.toLowerCase(), value)
    );

    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'defaultPercentage': defaultPercentage,
      'billPercentages': encodedMap,
      'amountPaid': amountPaid,
      'lastPaymentDate': lastPaymentDate
    };
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