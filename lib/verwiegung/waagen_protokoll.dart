/// Ein Messwert der Waage. Immer als Brutto-Gewicht in Gramm - das Tarieren
/// (Nullstellen auf die leere Wanne) macht die Software, nicht die Waage.
class Waagenwert {
  final double gramm;
  final bool stabil;
  final DateTime zeit;

  /// Rohe Zeile der Waage (nur für Diagnose/Anzeige).
  final String? roh;

  const Waagenwert({required this.gramm, required this.stabil, required this.zeit, this.roh});

  @override
  String toString() => 'Waagenwert(${gramm.toStringAsFixed(1)} g, ${stabil ? 'stabil' : 'instabil'})';
}

/// Liest die Textzeilen der Ohaus-Waage (RS-232-Dauerausgabe).
///
/// Am GerÃ¤t bestÃ¤tigtes Format (T32XW, 30.10.2026): `"   0.065 kg    G\r\n"`,
/// instabil mit "?" hinter der Einheit. Die Leitung liefert gelegentlich
/// StÃ¶rbytes und abgeschnittene Zeilen. Eine Zeile zÃ¤hlt deshalb nur, wenn sie
/// vollstÃ¤ndig dem Muster entspricht: Zahl, Einheit (Pflicht - eine abgeschnittene
/// Zeile wie "0.0" darf nicht als 0 g durchgehen), danach hÃ¶chstens "?"/"US"
/// und eine kurze Legende (G, N, NET, T). Alles andere ergibt null.
class WaagenProtokoll {
  static final _zeile = RegExp(
    r'^\s*([+-]?\s*\d+(?:[.,]\d+)?)\s*(kg|g|lb|oz)((?:\s*(?:\?|US))?(?:\s+[A-Z]{1,3})?(?:\s*(?:\?|US))?)\s*$',
    caseSensitive: false,
  );
  static final _druckbar = RegExp(r'^[\x20-\x7E]*$');

  /// Gibt null zurÃ¼ck, wenn die Zeile kein vollstÃ¤ndiges Gewicht enthÃ¤lt
  /// (Leerzeile, Fehlermeldung "ES"/"Err 8.1", StÃ¶rbytes, abgeschnittene Zeile).
  static Waagenwert? parseZeile(String zeile, DateTime zeit) {
    if (!_druckbar.hasMatch(zeile.replaceAll(RegExp(r'[\r\n]+$'), ''))) return null;
    final treffer = _zeile.firstMatch(zeile);
    if (treffer == null) return null;

    final zahlText = treffer.group(1)!.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    final zahl = double.tryParse(zahlText);
    if (zahl == null) return null;

    final double gramm;
    switch (treffer.group(2)!.toLowerCase()) {
      case 'kg':
        gramm = zahl * 1000;
        break;
      case 'lb':
        gramm = zahl * 453.59237;
        break;
      case 'oz':
        gramm = zahl * 28.349523125;
        break;
      default:
        gramm = zahl;
    }

    final rest = (treffer.group(3) ?? '').toUpperCase();
    final instabil = rest.contains('?') || RegExp(r'\bUS\b').hasMatch(rest);

    return Waagenwert(gramm: gramm, stabil: !instabil, zeit: zeit, roh: zeile.trim());
  }
}