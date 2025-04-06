class Bill {
  final int? id;
  final String company;
  final double amount;
  final String dueDate;
  final String status;
  final String? notes;

  Bill({this.id, required this.company, required this.amount, required this.dueDate, required this.status, required this.notes});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company': company,
      'amount': amount,
      'dueDate': dueDate,
      'status': status,
      'notes': notes
    };
  }

  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'],
      company: map['company'],
      amount: map['amount'],
      dueDate: map['dueDate'],
      status: map['status'],
      notes: map['notes']
    );
  }
}