/// Was die Lampen am Schütten-Regal gerade anzeigen sollen.
enum LampenModus {
  aus, // keine Verwiegung aktiv
  alleRot, // alle Positionen rot (z.B. Schritt ohne Lampe)
  einsGruen, // alle rot, nur [LampenAnweisung.position] grün
  fehler, // alle rot blinkend: Verbindung/Waage gestört, nicht weiterarbeiten
}

class LampenAnweisung {
  final LampenModus modus;
  final int? position;

  const LampenAnweisung(this.modus, [this.position]);

  static const aus = LampenAnweisung(LampenModus.aus);
  static const alleRot = LampenAnweisung(LampenModus.alleRot);
  static const fehler = LampenAnweisung(LampenModus.fehler);
  factory LampenAnweisung.nurGruen(int position) =>
      LampenAnweisung(LampenModus.einsGruen, position);

  @override
  bool operator ==(Object other) =>
      other is LampenAnweisung && other.modus == modus && other.position == position;

  @override
  int get hashCode => Object.hash(modus, position);

  @override
  String toString() => 'LampenAnweisung($modus, $position)';
}

/// Schnittstelle zum LED-Knoten. Die erste Umsetzung ist nur die Simulation
/// auf dem Bildschirm; später kommt eine WebSocket-Anbindung an den ESP32.
abstract class LampenSteuerung {
  Future<void> setze(LampenAnweisung anweisung);
}

/// Hält die letzte Anweisung - für die Bildschirmsimulation und Tests.
class SimulierteLampen implements LampenSteuerung {
  LampenAnweisung aktuell = LampenAnweisung.aus;

  @override
  Future<void> setze(LampenAnweisung anweisung) async {
    aktuell = anweisung;
  }
}
