class BestandProdukt {
  final String id;
  final String name;
  final bool aktiv;
  final int reihenfolge;

  BestandProdukt({
    required this.id,
    required this.name,
    required this.aktiv,
    required this.reihenfolge,
  });

  factory BestandProdukt.fromJson(Map<String, dynamic> json) => BestandProdukt(
        id: json['id'] as String,
        name: json['name'] as String,
        aktiv: json['aktiv'] as bool? ?? true,
        reihenfolge: json['reihenfolge'] as int? ?? 0,
      );
}

/// Träger, auf dem ein Produkt gezählt wird. Jedes Produkt wird auf beiden
/// Trägern produziert, die Wahl erfolgt bei der Zählung durch den Anwender.
enum Traeger {
  blech('Blech'),
  diele('Diele');

  final String wert;
  const Traeger(this.wert);
}

/// Eine Bestandszaehlungs-Zeile: immer der aktuellste (einzige) Wert je
/// Produkt, Posten und Träger - kein Verlauf mehr.
class BestandEintrag {
  final String produktId;
  final String produktName;
  final String traeger;
  final double menge;
  final DateTime aktualisiertAm;

  BestandEintrag({
    required this.produktId,
    required this.produktName,
    required this.traeger,
    required this.menge,
    required this.aktualisiertAm,
  });

  factory BestandEintrag.fromJson(Map<String, dynamic> json) {
    // Erwartet einen verschachtelten Select: bestandszaehlungen.*,
    // bestand_produkte(name)
    final produkt = json['bestand_produkte'] as Map<String, dynamic>?;
    return BestandEintrag(
      produktId: json['produkt_id'] as String,
      produktName: produkt?['name'] as String? ?? json['produkt_name'] as String? ?? '?',
      traeger: json['traeger'] as String,
      menge: (json['menge'] as num).toDouble(),
      aktualisiertAm: DateTime.parse(json['aktualisiert_am'] as String),
    );
  }
}
