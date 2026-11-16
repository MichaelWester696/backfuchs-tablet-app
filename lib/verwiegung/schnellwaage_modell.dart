import 'waagen_protokoll.dart';

/// Zustand der Schnellwaage im Rezept: letzter Messwert und Tara.
///
/// Die Tara ist reine Software (wie in der geführten Verwiegung): beim
/// Tarieren merkt sich die App das aktuelle Bruttogewicht und zieht es ab.
/// Die Waage selbst wird nicht verändert.
class SchnellWaageModell {
  /// So lange gilt ein Messwert als aktuell; danach zeigt die Anzeige "keine Daten".
  static const frischeGrenze = Duration(seconds: 3);

  Waagenwert? _letzter;
  double _taraG = 0;

  Waagenwert? get letzter => _letzter;

  /// Abgezogenes Gewicht in Gramm (0 = nicht tariert).
  double get taraG => _taraG;
  bool get tariert => _taraG != 0;

  void neuerWert(Waagenwert wert) => _letzter = wert;

  /// Vergisst Messwert und Tara (neue Verbindung, andere Wanne).
  void zuruecksetzen() {
    _letzter = null;
    _taraG = 0;
  }

  bool hatAktuellenWert(DateTime jetzt) {
    final w = _letzter;
    return w != null && jetzt.difference(w.zeit) <= frischeGrenze;
  }

  /// Angezeigtes Gewicht in Gramm (brutto minus Tara) oder null ohne aktuellen Messwert.
  double? nettoG(DateTime jetzt) => hatAktuellenWert(jetzt) ? _letzter!.gramm - _taraG : null;

  bool stabil(DateTime jetzt) => hatAktuellenWert(jetzt) && _letzter!.stabil;

  /// Setzt die Anzeige auf 0. Ohne aktuellen Messwert passiert nichts (false).
  bool tarieren(DateTime jetzt) {
    if (!hatAktuellenWert(jetzt)) return false;
    _taraG = _letzter!.gramm;
    return true;
  }

  void taraLoeschen() => _taraG = 0;

  /// "1,234 kg" mit drei Nachkommastellen wie in der Zutatenliste; "0,000 kg" statt "-0,000 kg".
  static String formatiere(double gramm) {
    final gerundet = gramm.roundToDouble();
    final betrag = (gerundet.abs() / 1000).toStringAsFixed(3).replaceAll('.', ',');
    return '${gerundet < 0 ? '-' : ''}$betrag kg';
  }
}
