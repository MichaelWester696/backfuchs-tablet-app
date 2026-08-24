class Aufgabe {
  final String id;
  final String postenId;
  final String titel;
  final String? beschreibung;
  final DateTime faelligkeitsdatum;
  final String? uhrzeit; // Format "HH:MM:SS" wie von Postgres `time` geliefert
  final String dringlichkeit; // 'niedrig' | 'normal' | 'hoch'
  final String status; // 'offen' | 'erledigt'
  final bool wiederkehrend;
  final String quelle; // 'manuell' | 'whatsapp' | 'system'
  final int reihenfolge; // manuell im Dashboard einstellbar
  final String? rezeptId; // verknüpftes Rezept, z.B. "wiege 5x Croissant ab"

  Aufgabe({
    required this.id,
    required this.postenId,
    required this.titel,
    this.beschreibung,
    required this.faelligkeitsdatum,
    this.uhrzeit,
    required this.dringlichkeit,
    required this.status,
    required this.wiederkehrend,
    required this.quelle,
    required this.reihenfolge,
    this.rezeptId,
  });

  bool get erledigt => status == 'erledigt';

  factory Aufgabe.fromJson(Map<String, dynamic> json) => Aufgabe(
        id: json['id'] as String,
        postenId: json['posten_id'] as String,
        titel: json['titel'] as String,
        beschreibung: json['beschreibung'] as String?,
        faelligkeitsdatum: DateTime.parse(json['faelligkeitsdatum'] as String),
        uhrzeit: json['uhrzeit'] as String?,
        dringlichkeit: json['dringlichkeit'] as String? ?? 'normal',
        status: json['status'] as String? ?? 'offen',
        wiederkehrend: json['wiederkehrend'] as bool? ?? false,
        quelle: json['quelle'] as String? ?? 'manuell',
        reihenfolge: json['reihenfolge'] as int? ?? 0,
        rezeptId: json['rezept_id'] as String?,
      );

  String get uhrzeitKurz {
    if (uhrzeit == null) return '';
    final teile = uhrzeit!.split(':');
    if (teile.length < 2) return uhrzeit!;
    return '${teile[0]}:${teile[1]} Uhr';
  }
}
