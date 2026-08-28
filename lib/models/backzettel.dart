/// Täglicher Produktionszettel aus dem ERP (Excel-Import im Dashboard).
/// Spalten/Zeilen bleiben generisch, damit sich die Struktur ändern kann,
/// ohne dass die App angepasst werden muss.
class Backzettel {
  final String id;
  final String arbeitsdatum; // ISO yyyy-MM-dd - der Tag, an dem der Zettel in der Backstube benutzt wird
  final String? produktionsdatum;
  final List<String> spalten;
  final List<Map<String, dynamic>> zeilen;
  final DateTime hochgeladenAm;
  final String quelle;

  Backzettel({
    required this.id,
    required this.arbeitsdatum,
    this.produktionsdatum,
    required this.spalten,
    required this.zeilen,
    required this.hochgeladenAm,
    required this.quelle,
  });

  factory Backzettel.fromJson(Map<String, dynamic> json) => Backzettel(
        id: json['id'] as String,
        arbeitsdatum: json['arbeitsdatum'] as String,
        produktionsdatum: json['produktionsdatum'] as String?,
        spalten: ((json['spalten'] as List?) ?? []).map((e) => e.toString()).toList(),
        zeilen: ((json['zeilen'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        hochgeladenAm: DateTime.parse(json['hochgeladen_am'] as String),
        quelle: json['quelle'] as String? ?? 'manuell',
      );
}
