import '../models/rezept.dart';
import 'rohstoffstamm.dart';

enum SchrittArt {
  wiegen, // Gewicht kommt von der Waage
  zaehlen, // Menge in Stück/TL/EL ...: Mitarbeiter bestätigt von Hand
}

/// Ein Arbeitsschritt am Verwiegeplatz: eine Zutat in die Wanne geben.
class Verwiegeschritt {
  final String zutatName;
  final Rohstoff? rohstoff; // null = Name steht nicht im Rohstoffstamm
  final Verwiegeposition? position; // null = keine Lampe zugeordnet
  final SchrittArt art;
  final double sollMenge; // Menge laut Rezept in der Rezepteinheit
  final String einheit;
  final double sollG; // nur bei SchrittArt.wiegen
  final double toleranzG;

  const Verwiegeschritt({
    required this.zutatName,
    required this.rohstoff,
    required this.position,
    required this.art,
    required this.sollMenge,
    required this.einheit,
    required this.sollG,
    required this.toleranzG,
  });

  /// Untergrenze des Annahmefensters. Mindestens die Hälfte der Sollmenge,
  /// damit kleine Mengen (Toleranz >= Soll) nicht schon bei 0 g "passen".
  double get fensterVonG {
    final ausToleranz = sollG - toleranzG;
    final haelfte = sollG / 2;
    return ausToleranz > haelfte ? ausToleranz : haelfte;
  }

  double get fensterBisG => sollG + toleranzG;
}

/// Zutat, die nicht am Verwiegeplatz bearbeitet wird (Mischer, Halbfabrikat ...).
class AndereZutat {
  final String name;
  final double menge;
  final String einheit;
  final RohstoffTyp typ;

  const AndereZutat({required this.name, required this.menge, required this.einheit, required this.typ});
}

class VerwiegePlan {
  final List<Verwiegeschritt> schritte;
  final List<AndereZutat> andereZutaten;

  /// Hinweise für die Leitung (z.B. Zutat nicht im Stamm, keine Lampe).
  final List<String> hinweise;

  const VerwiegePlan({required this.schritte, required this.andereZutaten, required this.hinweise});

  double get summeSollG => schritte
      .where((s) => s.art == SchrittArt.wiegen)
      .fold(0.0, (summe, s) => summe + s.sollG);

  /// [mengeFuer] liefert die auf den Ansatz umgerechnete Menge einer Zutat
  /// (dieselbe Rechnung wie die Rezeptanzeige, damit beide übereinstimmen).
  static VerwiegePlan erstellen({
    required Rezept rezept,
    required double Function(Zutat) mengeFuer,
    required Rohstoffstamm stamm,
  }) {
    final schritte = <Verwiegeschritt>[];
    final andere = <AndereZutat>[];
    final hinweise = <String>[];
    void hinweisMerken(String text) {
      if (!hinweise.contains(text)) hinweise.add(text);
    }

    for (final z in rezept.zutaten) {
      final menge = mengeFuer(z);
      if (menge <= 0) continue;

      final rohstoff = stamm.finde(z.name);
      if (rohstoff != null) {
        if (!rohstoff.aktiv || rohstoff.typ == RohstoffTyp.ignorieren) continue;
        if (rohstoff.typ != RohstoffTyp.verwiegung) {
          andere.add(AndereZutat(name: z.name, menge: menge, einheit: z.einheit, typ: rohstoff.typ));
          continue;
        }
      } else {
        hinweisMerken('"${z.name}" steht nicht im Rohstoffstamm - bitte die Leitung informieren.');
      }

      final position = rohstoff == null ? null : stamm.positionFuer(rohstoff);
      if (rohstoff != null && position == null) {
        hinweisMerken('"${rohstoff.name}" hat noch keine Lampe (Position) zugeordnet.');
      }

      final gramm = _inGramm(menge, z.einheit);
      if (gramm == null) {
        schritte.add(Verwiegeschritt(
          zutatName: z.name,
          rohstoff: rohstoff,
          position: position,
          art: SchrittArt.zaehlen,
          sollMenge: menge,
          einheit: z.einheit,
          sollG: 0,
          toleranzG: 0,
        ));
        continue;
      }

      final soll = (gramm * 10).round() / 10;
      final standard = rohstoff ?? const Rohstoff(id: '', name: '', typ: RohstoffTyp.verwiegung);
      schritte.add(Verwiegeschritt(
        zutatName: z.name,
        rohstoff: rohstoff,
        position: position,
        art: SchrittArt.wiegen,
        sollMenge: menge,
        einheit: z.einheit,
        sollG: soll,
        toleranzG: standard.toleranzFuer(soll),
      ));
    }

    if (schritte.isEmpty) {
      hinweisMerken('Dieses Rezept hat keine Zutaten für den Verwiegeplatz.');
    }

    return VerwiegePlan(schritte: schritte, andereZutaten: andere, hinweise: hinweise);
  }

  static double? _inGramm(double menge, String einheit) {
    switch (einheit.trim().toLowerCase()) {
      case 'g':
        return menge;
      case 'kg':
        return menge * 1000;
      default:
        return null;
    }
  }
}
