import 'waagen_protokoll.dart';

/// Letzter Herzschlag des Waagen-Knotens (`#hb ...`, jede Sekunde).
class KnotenHerzschlag {
  final DateTime empfangen;
  final int betriebsSekunden;

  /// Millisekunden seit der letzten gültigen Zeile der Waage, null wenn der
  /// Knoten seit dem Start noch keine Zeile gesehen hat.
  final int? msSeitLetzterZeile;
  final int verworfeneZeilen;

  const KnotenHerzschlag({
    required this.empfangen,
    required this.betriebsSekunden,
    required this.msSeitLetzterZeile,
    required this.verworfeneZeilen,
  });
}

/// Wertet die Textnachrichten des Waagen-Knotens aus (WebSocket, reiner Text).
///
/// Der Knoten schickt jede Zeile der Waage unverändert (ca. 50 pro Sekunde) und
/// jede Sekunde einen Herzschlag `#hb <Betriebs-s> <ms seit letzter Zeile>
/// <verworfen> ...`. Gewichtszeilen prüft der strenge [WaagenProtokoll]-Parser;
/// was nicht vollständig passt, wird gezählt und verworfen.
///
/// Damit die Oberfläche nicht 50-mal pro Sekunde neu zeichnet, werden Werte
/// höchstens alle [mindestAbstand] weitergegeben. Ein Wechsel zwischen stabil
/// und instabil geht immer sofort durch, weil er für die Verwiegung zählt.
class WaagenNachrichten {
  final Duration mindestAbstand;

  DateTime? _letzteMeldung;
  bool? _letzteStabil;

  /// Gewichtszeilen, die der Parser nicht angenommen hat (Störungen).
  int verworfeneZeilen = 0;

  KnotenHerzschlag? herzschlag;

  WaagenNachrichten({this.mindestAbstand = const Duration(milliseconds: 100)});

  /// Gibt einen neuen Messwert zurück oder null (Herzschlag, Meldung,
  /// verworfene Zeile oder zu dicht auf den vorigen Wert folgend).
  Waagenwert? verarbeite(String nachricht, DateTime jetzt) {
    if (nachricht.startsWith('#')) {
      if (nachricht.startsWith('#hb')) _herzschlag(nachricht, jetzt);
      return null;
    }

    final wert = WaagenProtokoll.parseZeile(nachricht, jetzt);
    if (wert == null) {
      verworfeneZeilen++;
      return null;
    }

    final letzte = _letzteMeldung;
    final wechsel = _letzteStabil != wert.stabil;
    if (!wechsel && letzte != null && jetzt.difference(letzte) < mindestAbstand) return null;

    _letzteMeldung = jetzt;
    _letzteStabil = wert.stabil;
    return wert;
  }

  void _herzschlag(String nachricht, DateTime jetzt) {
    final teile = nachricht.trim().split(RegExp(r'\s+'));
    if (teile.length < 4) return;
    final betrieb = int.tryParse(teile[1]);
    final alter = int.tryParse(teile[2]);
    final verworfen = int.tryParse(teile[3]);
    if (betrieb == null || alter == null || verworfen == null) return;
    herzschlag = KnotenHerzschlag(
      empfangen: jetzt,
      betriebsSekunden: betrieb,
      msSeitLetzterZeile: alter < 0 ? null : alter,
      verworfeneZeilen: verworfen,
    );
  }
}
