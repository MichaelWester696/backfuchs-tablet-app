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

/// Liest die Textzeilen der Ohaus-Waage (RS-232-Ausgabe, z.B. über Befehl CP).
///
/// Das genaue Zeilenformat der Defender 3000 Xtreme W (T32XW-EU) ist noch
/// nicht am Gerät bestätigt (Test mit verwiegung/waage-test.ps1). Der Parser
/// ist deshalb bewusst tolerant: Er sucht die erste Zahl, danach eine
/// optionale Einheit (g/kg/lb/oz) und wertet "?" bzw. "US" im Rest der Zeile
/// als "instabil". Ohne Einheit wird Gramm angenommen.
class WaagenProtokoll {
  static final _zeile = RegExp(
    r'^\s*([+-]?\s*\d+(?:[.,]\d+)?)\s*(kg|g|lb|oz)?(.*)$',
    caseSensitive: false,
  );

  /// Gibt null zurück, wenn die Zeile kein Gewicht enthält (z.B. Leerzeile,
  /// Fehlermeldung "Err 8.1" oder Kopfzeilen).
  static Waagenwert? parseZeile(String zeile, DateTime zeit) {
    final treffer = _zeile.firstMatch(zeile);
    if (treffer == null) return null;

    final zahlText = treffer.group(1)!.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    final zahl = double.tryParse(zahlText);
    if (zahl == null) return null;

    final einheit = (treffer.group(2) ?? 'g').toLowerCase();
    final double gramm;
    switch (einheit) {
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
