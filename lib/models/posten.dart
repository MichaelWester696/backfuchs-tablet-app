class Posten {
  final String id;
  final String name;
  final bool aktiv;
  final int reihenfolge;
  final bool zeigtRezepte;

  Posten({
    required this.id,
    required this.name,
    required this.aktiv,
    required this.reihenfolge,
    required this.zeigtRezepte,
  });

  factory Posten.fromJson(Map<String, dynamic> json) => Posten(
        id: json['id'] as String,
        name: json['name'] as String,
        aktiv: json['aktiv'] as bool? ?? true,
        reihenfolge: json['reihenfolge'] as int? ?? 0,
        zeigtRezepte: json['zeigt_rezepte'] as bool? ?? true,
      );
}
