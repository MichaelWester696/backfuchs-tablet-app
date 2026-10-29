/// Wie ein Rohstoff behandelt wird. Spiegelt die Spalte rohstoffe.typ.
enum RohstoffTyp {
  verwiegung, // wird am Verwiegeplatz gewogen
  mischer, // geht direkt in den Mischer (Mehl, Wasser, Ei ...)
  halbfabrikat, // Vorteig, Kochstück ... (anderer Arbeitsgang)
  stueckware, // wird gezählt, nicht gewogen
  ignorieren; // Testmüll in den Rezepten

  static RohstoffTyp ausText(String? text) {
    for (final t in RohstoffTyp.values) {
      if (t.name == text) return t;
    }
    return RohstoffTyp.verwiegung;
  }
}

class Rohstoff {
  final String id;
  final String name;
  final RohstoffTyp typ;
  final double toleranzProzent;
  final double toleranzMinG;
  final bool aktiv;

  const Rohstoff({
    required this.id,
    required this.name,
    required this.typ,
    this.toleranzProzent = 2,
    this.toleranzMinG = 2,
    this.aktiv = true,
  });

  factory Rohstoff.fromJson(Map<String, dynamic> json) => Rohstoff(
        id: json['id'] as String,
        name: json['name'] as String,
        typ: RohstoffTyp.ausText(json['typ'] as String?),
        toleranzProzent: (json['toleranz_prozent'] as num?)?.toDouble() ?? 2,
        toleranzMinG: (json['toleranz_min_g'] as num?)?.toDouble() ?? 2,
        aktiv: json['aktiv'] as bool? ?? true,
      );

  /// Erlaubte Abweichung für eine Sollmenge: der größere Wert aus dem
  /// Prozentsatz und dem Mindestwert in Gramm (bei kleinen Mengen zählt der
  /// Mindestwert, sonst wäre das Fenster kleiner als die Waagenauflösung).
  double toleranzFuer(double sollG) {
    final ausProzent = sollG * toleranzProzent / 100;
    return ausProzent > toleranzMinG ? ausProzent : toleranzMinG;
  }
}

/// Ein Platz mit Lampe: Schütte 1-20 oder freie Zutat (Hefe, Margarine ...).
class Verwiegeposition {
  final int nr; // Lampennummer = Reihenfolge im LED-Streifen
  final String art; // 'schuette' | 'frei'
  final String bezeichnung;
  final String? rohstoffId;

  const Verwiegeposition({
    required this.nr,
    required this.art,
    required this.bezeichnung,
    this.rohstoffId,
  });

  factory Verwiegeposition.fromJson(Map<String, dynamic> json) => Verwiegeposition(
        nr: (json['nr'] as num).toInt(),
        art: json['art'] as String? ?? 'schuette',
        bezeichnung: json['bezeichnung'] as String? ?? 'Position ${json['nr']}',
        rohstoffId: json['rohstoff_id'] as String?,
      );
}

/// Rohstoffstamm: ordnet die Freitext-Zutatennamen der Rezepte einem
/// Rohstoff zu und diesen einer Position (Lampe).
class Rohstoffstamm {
  final Map<String, Rohstoff> _nachId;
  final Map<String, String> _aliasZuId; // exakter Zutatenname -> Rohstoff-ID
  final Map<String, String> _schluesselZuId; // normalisierter Name -> Rohstoff-ID
  final Map<String, Verwiegeposition> _positionNachRohstoff;
  final List<Verwiegeposition> positionen;

  Rohstoffstamm._(
    this._nachId,
    this._aliasZuId,
    this._schluesselZuId,
    this._positionNachRohstoff,
    this.positionen,
  );

  factory Rohstoffstamm.leer() =>
      Rohstoffstamm.ausListen(rohstoffe: const [], aliase: const {}, positionen: const []);

  factory Rohstoffstamm.ausListen({
    required List<Rohstoff> rohstoffe,
    required Map<String, String> aliase,
    required List<Verwiegeposition> positionen,
  }) {
    final nachId = {for (final r in rohstoffe) r.id: r};

    final schluessel = <String, String>{};
    for (final r in rohstoffe) {
      schluessel.putIfAbsent(schluesselVon(r.name), () => r.id);
    }
    aliase.forEach((alias, id) {
      schluessel.putIfAbsent(schluesselVon(alias), () => id);
    });

    final nachRohstoff = <String, Verwiegeposition>{};
    for (final p in positionen) {
      final id = p.rohstoffId;
      if (id != null) nachRohstoff.putIfAbsent(id, () => p);
    }

    return Rohstoffstamm._(nachId, Map.of(aliase), schluessel, nachRohstoff, positionen);
  }

  /// Rohe Zeilen aus Supabase (oder dem Cache) -> Stamm.
  factory Rohstoffstamm.ausJson({
    required List<Map<String, dynamic>> rohstoffe,
    required List<Map<String, dynamic>> aliase,
    required List<Map<String, dynamic>> positionen,
  }) {
    return Rohstoffstamm.ausListen(
      rohstoffe: rohstoffe.map(Rohstoff.fromJson).toList(),
      aliase: {for (final a in aliase) a['alias'] as String: a['rohstoff_id'] as String},
      positionen: positionen.map(Verwiegeposition.fromJson).toList()
        ..sort((a, b) => a.nr.compareTo(b.nr)),
    );
  }

  bool get istLeer => _nachId.isEmpty;

  /// Gleiche Normalisierung wie im Dashboard (rohstoffSchluessel): klein,
  /// Umlaute aufgelöst, Wörter sortiert - so findet "Mehl Roggen" auch
  /// "Roggenmehl"-ähnliche Schreibweisen mit vertauschter Wortfolge.
  static String schluesselVon(String name) {
    final gefaltet = name
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    final woerter = gefaltet.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList()
      ..sort();
    final zusammen = woerter.join();
    return zusammen.isEmpty ? gefaltet : zusammen;
  }

  /// Sucht den Rohstoff zu einem Zutatennamen aus dem Rezept.
  Rohstoff? finde(String zutatName) {
    final name = zutatName.trim();
    final exakt = _aliasZuId[name];
    final id = exakt ?? _schluesselZuId[schluesselVon(name)];
    return id == null ? null : _nachId[id];
  }

  Verwiegeposition? positionFuer(Rohstoff rohstoff) => _positionNachRohstoff[rohstoff.id];
}
