import 'dart:async';

import 'waagen_protokoll.dart';

/// Quelle der Messwerte. Aktuell gibt es nur die Simulation; die echte
/// Waage (ESP32-Waagenknoten per WebSocket) wird später als weitere
/// Implementierung ergänzt, ohne dass sich Sitzung und Bildschirm ändern.
abstract class Waage {
  Stream<Waagenwert> get werte;
  Future<void> verbinden();
  Future<void> trennen();
}

/// Waage zum Ausprobieren ohne Hardware: Gewicht wird per Knopfdruck oder
/// Eingabe verändert und regelmäßig wie von einer echten Waage gemeldet.
class SimulierteWaage implements Waage {
  final Duration takt;
  final _controller = StreamController<Waagenwert>.broadcast();
  Timer? _timer;
  double _gramm = 0;
  DateTime _letzteAenderung = DateTime.fromMillisecondsSinceEpoch(0);

  /// So lange nach einer Änderung meldet die Simulation "instabil".
  final Duration beruhigungszeit;

  bool unterbrochen = false;

  SimulierteWaage({
    this.takt = const Duration(milliseconds: 200),
    this.beruhigungszeit = const Duration(milliseconds: 500),
  });

  double get gramm => _gramm;

  @override
  Stream<Waagenwert> get werte => _controller.stream;

  @override
  Future<void> verbinden() async {
    _timer?.cancel();
    _timer = Timer.periodic(takt, (_) => _senden());
  }

  @override
  Future<void> trennen() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }

  void setzeGramm(double wert) {
    _gramm = wert;
    _letzteAenderung = DateTime.now();
  }

  void aendere(double differenz) => setzeGramm(_gramm + differenz);

  void _senden() {
    if (unterbrochen || _controller.isClosed) return;
    final jetzt = DateTime.now();
    final stabil = jetzt.difference(_letzteAenderung) >= beruhigungszeit;
    _controller.add(Waagenwert(
      gramm: _gramm,
      stabil: stabil,
      zeit: jetzt,
      roh: '${(_gramm / 1000).toStringAsFixed(3)} kg ${stabil ? '' : '?'}',
    ));
  }
}
