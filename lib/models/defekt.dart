class Defekt {
  final String id;
  final String postenId;
  final String maschine;
  final String beschreibung;
  final String? fotoUrl;
  final String status; // 'gemeldet' | 'in_bearbeitung' | 'behoben'
  final DateTime gemeldetAm;

  Defekt({
    required this.id,
    required this.postenId,
    required this.maschine,
    required this.beschreibung,
    this.fotoUrl,
    required this.status,
    required this.gemeldetAm,
  });

  factory Defekt.fromJson(Map<String, dynamic> json) => Defekt(
        id: json['id'] as String,
        postenId: json['posten_id'] as String,
        maschine: json['maschine'] as String,
        beschreibung: json['beschreibung'] as String,
        fotoUrl: json['foto_url'] as String?,
        status: json['status'] as String? ?? 'gemeldet',
        gemeldetAm: DateTime.parse(json['gemeldet_am'] as String),
      );
}
