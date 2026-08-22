class Defekt {
  final String id;
  final String postenId;
  final String? postenName;
  final String maschine;
  final String beschreibung;
  final String? fotoUrl;
  final String status; // 'gemeldet' | 'in_bearbeitung' | 'behoben'
  final DateTime gemeldetAm;
  final DateTime? behobenAm;

  Defekt({
    required this.id,
    required this.postenId,
    this.postenName,
    required this.maschine,
    required this.beschreibung,
    this.fotoUrl,
    required this.status,
    required this.gemeldetAm,
    this.behobenAm,
  });

  factory Defekt.fromJson(Map<String, dynamic> json) {
    // Erwartet optional einen verschachtelten Select: defekte.*, posten:posten_id(name)
    final posten = json['posten'] as Map<String, dynamic>?;
    return Defekt(
      id: json['id'] as String,
      postenId: json['posten_id'] as String,
      postenName: posten?['name'] as String?,
      maschine: json['maschine'] as String,
      beschreibung: json['beschreibung'] as String,
      fotoUrl: json['foto_url'] as String?,
      status: json['status'] as String? ?? 'gemeldet',
      gemeldetAm: DateTime.parse(json['gemeldet_am'] as String),
      behobenAm: json['behoben_am'] != null ? DateTime.parse(json['behoben_am'] as String) : null,
    );
  }
}
