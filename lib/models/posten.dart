class Posten {
  final String id;
  final String name;
  final bool aktiv;
  final int reihenfolge;

  Posten({required this.id, required this.name, required this.aktiv, required this.reihenfolge});

  factory Posten.fromJson(Map<String, dynamic> json) => Posten(
        id: json['id'] as String,
        name: json['name'] as String,
        aktiv: json['aktiv'] as bool? ?? true,
        reihenfolge: json['reihenfolge'] as int? ?? 0,
      );
}
