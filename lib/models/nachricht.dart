class Nachricht {
  final String id;
  final String? vonPostenId;
  final String zielTyp; // 'posten' | 'leitung'
  final String? anPostenId;
  final String text;
  final String? fotoUrl;
  final bool gelesen;
  final DateTime erstelltAm;

  Nachricht({
    required this.id,
    this.vonPostenId,
    required this.zielTyp,
    this.anPostenId,
    required this.text,
    this.fotoUrl,
    required this.gelesen,
    required this.erstelltAm,
  });

  factory Nachricht.fromJson(Map<String, dynamic> json) => Nachricht(
        id: json['id'] as String,
        vonPostenId: json['von_posten_id'] as String?,
        zielTyp: json['ziel_typ'] as String,
        anPostenId: json['an_posten_id'] as String?,
        text: json['text'] as String,
        fotoUrl: json['foto_url'] as String?,
        gelesen: json['gelesen'] as bool? ?? false,
        erstelltAm: DateTime.parse(json['erstellt_am'] as String),
      );
}
