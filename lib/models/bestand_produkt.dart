class BestandProdukt {
  final String id;
  final String name;
  final String einheit; // 'Blech' | 'Diele'
  final bool aktiv;
  final int reihenfolge;

  BestandProdukt({
    required this.id,
    required this.name,
    required this.einheit,
    required this.aktiv,
    required this.reihenfolge,
  });

  factory BestandProdukt.fromJson(Map<String, dynamic> json) => BestandProdukt(
        id: json['id'] as String,
        name: json['name'] as String,
        einheit: json['einheit'] as String? ?? 'Blech',
        aktiv: json['aktiv'] as bool? ?? true,
        reihenfolge: json['reihenfolge'] as int? ?? 0,
      );
}

/// Eine Bestandszaehlungs-Zeile: immer der aktuellste (einzige) Wert je
/// Produkt und Posten - kein Verlauf mehr.
class BestandEintrag {
  final String produktId;
  final String produktName;
  final String einheit;
  final double menge;
  final DateTime aktualisiertAm;

  BestandEintrag({
    required this.produktId,
    required this.produktName,
    required this.einheit,
    required this.menge,
    required this.aktualisiertAm,
  });

  factory BestandEintrag.fromJson(Map<String, dynamic> json) {
    // Erwartet einen verschachtelten Select: bestandszaehlungen.*,
    // bestand_produkte(name, einheit)
    final produkt = json['bestand_produkte'] as Map<String, dynamic>?;
    return BestandEintrag(
      produktId: json['produkt_id'] as String,
      produktName: produkt?['name'] as String? ?? json['produkt_name'] as String? ?? '?',
      einheit: produkt?['einheit'] as String? ?? json['einheit'] as String? ?? 'Blech',
      menge: (json['menge'] as num).toDouble(),
      aktualisiertAm: DateTime.parse(json['aktualisiert_am'] as String),
    );
  }
}
