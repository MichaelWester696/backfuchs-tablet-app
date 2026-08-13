class Zutat {
  final double menge;
  final String einheit;
  final String name;

  Zutat({required this.menge, required this.einheit, required this.name});

  factory Zutat.fromJson(Map<String, dynamic> json) => Zutat(
        menge: (json['menge'] as num).toDouble(),
        einheit: json['einheit'] as String,
        name: json['name'] as String,
      );
}

class Arbeitsschritt {
  final String text;
  final bool fix; // true = wird bei Stückzahl-Skalierung NICHT verändert (z.B. Temperaturen/Zeiten)

  Arbeitsschritt({required this.text, required this.fix});

  factory Arbeitsschritt.fromJson(Map<String, dynamic> json) => Arbeitsschritt(
        text: json['text'] as String,
        fix: json['fix'] as bool? ?? false,
      );
}

class Rezept {
  final String id;
  final String name;
  final int basisStueckzahl;
  final List<Zutat> zutaten;
  final List<Arbeitsschritt> schritte;

  Rezept({
    required this.id,
    required this.name,
    required this.basisStueckzahl,
    required this.zutaten,
    required this.schritte,
  });

  factory Rezept.fromJson(Map<String, dynamic> json) => Rezept(
        id: json['id'] as String,
        name: json['name'] as String,
        basisStueckzahl: json['basis_stueckzahl'] as int? ?? 1,
        zutaten: ((json['zutaten'] as List?) ?? [])
            .map((z) => Zutat.fromJson(z as Map<String, dynamic>))
            .toList(),
        schritte: ((json['schritte'] as List?) ?? [])
            .map((s) => Arbeitsschritt.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  /// Rechnet eine Zutatenmenge auf eine Zielstückzahl um.
  /// Entspricht der Logik der bestehenden Web-Admin-Oberfläche:
  /// neue_menge = basis_menge * (ziel_stueckzahl / basis_stueckzahl)
  double umgerechneteMenge(Zutat zutat, int zielStueckzahl) {
    if (basisStueckzahl == 0) return zutat.menge;
    return zutat.menge * (zielStueckzahl / basisStueckzahl);
  }

  /// Formatiert eine Menge inkl. Einheiten-Intelligenz (g -> kg ab 1000g,
  /// ml -> l ab 1000ml), analog zur Web-Oberfläche.
  String formatiereMenge(double menge, String einheit) {
    double wert = menge;
    String einh = einheit;

    if (einheit == 'g' && menge >= 1000) {
      wert = menge / 1000;
      einh = 'kg';
    } else if (einheit == 'ml' && menge >= 1000) {
      wert = menge / 1000;
      einh = 'l';
    }

    final gerundet = (wert * 100).round() / 100;
    final text = gerundet == gerundet.roundToDouble()
        ? gerundet.toStringAsFixed(0)
        : gerundet.toString();
    return '$text $einh';
  }
}
