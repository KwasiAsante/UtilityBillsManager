class Rentor {
  final int? id;
  final String name;
  final double percentage;

  Rentor({this.id, required this.name, required this.percentage});

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'percentage': percentage};
  }

  factory Rentor.fromMap(Map<String, dynamic> map) {
    return Rentor(
      id: map['id'],
      name: map['name'],
      percentage: map['percentage'],
    );
  }
}
