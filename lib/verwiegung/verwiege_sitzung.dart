import 'lampen.dart';
import 'verwiege_plan.dart';
import 'waagen_protokoll.dart';

enum SitzungsPhase { vorbereitung, laeuft, fertig, abgebrochen }

/// Was der Mitarbeiter gerade sehen soll (bestimmt Farbe und Hinweistext).
enum Anzeigezustand {
  keineWaage, // keine (aktuellen) Messwerte
  wanneFehlt, // Gewicht liegt deutlich unter dem Ausgangsgewicht
  zuWenig, // unterhalb des Annahmefensters
  imFenster, // im Fenster, Haltezeit läuft
  zuViel, // oberhalb des Fensters
}

class SchrittErgebnis {
  final Verwiegeschritt schritt;
  final double? istG; // null bei SchrittArt.zaehlen
  final DateTime bestaetigtUm;

  const SchrittErgebnis({required this.schritt, required this.istG, required this.bestaetigtUm});

  Map<String, dynamic> toJson() => {
        'zutat': schritt.zutatName,
        'rohstoff_id': schritt.rohstoff?.id,
        'position': schritt.position?.nr,
        'art': schritt.art.name,
        'soll_menge': schritt.sollMenge,
        'einheit': schritt.einheit,
        'soll_g': schritt.art == SchrittArt.wiegen ? schritt.sollG : null,
        'toleranz_g': schritt.art == SchrittArt.wiegen ? schritt.toleranzG : null,
        'ist_g': istG,
        'bestaetigt_um': bestaetigtUm.toUtc().toIso8601String(),
      };
}

/// Ablaufsteuerung einer Verwiegung (Zustandsmaschine, ohne Flutter-Bezug).
///
/// Ablauf: Wanne auf die Waage -> [start] (Software-Tara auf das aktuelle
/// Bruttogewicht) -> je Schritt wiegen, bis das Gewicht eine Haltezeit lang
/// stabil im Annahmefenster liegt -> automatisch weiter zum nächsten Schritt.
/// Die Wanne bleibt auf der Waage, jeder Schritt misst relativ zum Gewicht
/// nach dem vorigen Schritt.
///
/// Zeitpunkte werden immer von außen übergeben, damit das Verhalten testbar ist.
class VerwiegeSitzung {
  final List<Verwiegeschritt> schritte;

  /// So lange muss das Gewicht stabil im Fenster liegen, bevor weitergeschaltet wird.
  final Duration haltezeit;

  /// Nach dieser Zeit ohne Messwert gilt die Waage als nicht verbunden.
  final Duration datenTimeout;

  /// Liegt das Gewicht um mehr als diesen Wert (g) unter dem Ausgangswert des
  /// Schritts, wurde vermutlich die Wanne abgenommen.
  final double wanneFehltG;

  SitzungsPhase phase = SitzungsPhase.vorbereitung;
  int index = 0;
  double basisG = 0;
  double startBruttoG = 0;
  DateTime? gestartetAm;
  DateTime? beendetAm;
  Waagenwert? letzter;
  final List<SchrittErgebnis> ergebnisse = [];

  void Function()? beiAenderung;

  DateTime? _fensterSeit;

  VerwiegeSitzung({
    required this.schritte,
    this.haltezeit = const Duration(milliseconds: 1200),
    this.datenTimeout = const Duration(seconds: 3),
    this.wanneFehltG = 100,
  });

  Verwiegeschritt? get aktuell =>
      phase == SitzungsPhase.laeuft && index < schritte.length ? schritte[index] : null;

  /// Netto-Gewicht des aktuellen Schritts (Bruttogewicht minus Ausgangswert).
  double? get istG => letzter == null ? null : letzter!.gramm - basisG;

  bool verbindungOk(DateTime jetzt) =>
      letzter != null && jetzt.difference(letzter!.zeit) <= datenTimeout;

  /// Start nur mit aktuellem, ruhigem Messwert - sonst wäre die Tara ungenau.
  bool kannStarten(DateTime jetzt) =>
      phase == SitzungsPhase.vorbereitung && verbindungOk(jetzt) && letzter!.stabil;

  bool start(DateTime jetzt) {
    if (!kannStarten(jetzt)) return false;
    basisG = letzter!.gramm;
    startBruttoG = basisG;
    gestartetAm = jetzt;
    index = 0;
    _fensterSeit = null;
    phase = schritte.isEmpty ? SitzungsPhase.fertig : SitzungsPhase.laeuft;
    if (phase == SitzungsPhase.fertig) beendetAm = jetzt;
    _melden();
    return true;
  }

  void messwert(Waagenwert wert) {
    letzter = wert;
    _pruefeBestaetigung(wert.zeit);
    _melden();
  }

  /// Regelmäßig aufrufen (z.B. alle 200 ms): lässt die Haltezeit auch dann
  /// ablaufen, wenn die Waage nur bei Änderungen sendet.
  void tick(DateTime jetzt) {
    _pruefeBestaetigung(jetzt);
    _melden();
  }

  /// Nur für Schritte ohne Waage (Stück, TL, EL ...). Ein Wiegeschritt lässt
  /// sich bewusst nicht von Hand überspringen.
  bool manuellBestaetigen(DateTime jetzt) {
    final s = aktuell;
    if (s == null || s.art != SchrittArt.zaehlen) return false;
    _bestaetige(null, jetzt);
    _melden();
    return true;
  }

  void abbrechen(DateTime jetzt) {
    if (phase == SitzungsPhase.fertig || phase == SitzungsPhase.abgebrochen) return;
    phase = SitzungsPhase.abgebrochen;
    beendetAm = jetzt;
    _melden();
  }

  Anzeigezustand zustand(DateTime jetzt) {
    final s = aktuell;
    if (!verbindungOk(jetzt)) return Anzeigezustand.keineWaage;
    final ist = istG!;
    if (ist < -wanneFehltG) return Anzeigezustand.wanneFehlt;
    if (s == null || s.art != SchrittArt.wiegen) return Anzeigezustand.zuWenig;
    if (ist > s.fensterBisG) return Anzeigezustand.zuViel;
    if (ist >= s.fensterVonG) return Anzeigezustand.imFenster;
    return Anzeigezustand.zuWenig;
  }

  /// Anteil der Haltezeit, der im Fenster schon abgelaufen ist (0..1).
  double haltefortschritt(DateTime jetzt) {
    final seit = _fensterSeit;
    if (seit == null || haltezeit.inMilliseconds == 0) return 0;
    final anteil = jetzt.difference(seit).inMilliseconds / haltezeit.inMilliseconds;
    return anteil < 0 ? 0 : (anteil > 1 ? 1 : anteil);
  }

  /// Gewünschter Lampenzustand. Bei Verbindungsproblemen sofort Fehler
  /// (alle rot blinkend): lieber stehen bleiben als mit falscher Anzeige weiterarbeiten.
  LampenAnweisung lampen(DateTime jetzt) {
    if (phase != SitzungsPhase.laeuft) return LampenAnweisung.aus;
    if (!verbindungOk(jetzt)) return LampenAnweisung.fehler;
    final nr = aktuell?.position?.nr;
    return nr == null ? LampenAnweisung.alleRot : LampenAnweisung.nurGruen(nr);
  }

  /// Fertiges Protokoll der gewogenen Mengen.
  List<Map<String, dynamic>> ergebnisseAlsJson() => ergebnisse.map((e) => e.toJson()).toList();

  void _pruefeBestaetigung(DateTime jetzt) {
    final s = aktuell;
    if (s == null || s.art != SchrittArt.wiegen) {
      _fensterSeit = null;
      return;
    }
    final messung = letzter;
    if (messung == null || !verbindungOk(jetzt)) {
      _fensterSeit = null;
      return;
    }

    final ist = messung.gramm - basisG;
    final imFenster = messung.stabil && ist >= s.fensterVonG && ist <= s.fensterBisG;
    if (!imFenster) {
      _fensterSeit = null;
      return;
    }

    _fensterSeit ??= jetzt;
    if (jetzt.difference(_fensterSeit!) >= haltezeit) {
      _bestaetige(ist, jetzt);
    }
  }

  void _bestaetige(double? ist, DateTime jetzt) {
    final s = schritte[index];
    ergebnisse.add(SchrittErgebnis(schritt: s, istG: ist, bestaetigtUm: jetzt));
    if (ist != null) basisG = letzter!.gramm; // nächster Schritt misst ab hier
    index++;
    _fensterSeit = null;
    if (index >= schritte.length) {
      phase = SitzungsPhase.fertig;
      beendetAm = jetzt;
    }
  }

  void _melden() => beiAenderung?.call();
}
