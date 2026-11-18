import 'dart:async';

import 'waage.dart';
import 'waagen_protokoll.dart';
import 'websocket_waage.dart';

/// Die eine Verbindung der App zum Waagen-Knoten.
///
/// Sie wird beim Start der App geöffnet und bleibt offen, solange die App im
/// Vordergrund ist - egal, ob gerade ein Rezept mit Schnellwaage oder die
/// geführte Verwiegung angezeigt wird. Beide hören nur an [werte] mit und
/// öffnen keine eigene Verbindung. Der Knoten bedient nur wenige Tablets
/// gleichzeitig, und jeder Verbindungsaufbau kostet beim Blättern Zeit, in der
/// kein Gewicht angezeigt werden könnte.
///
/// [werte] bleibt beim Anhalten und Neustarten bestehen, die Zuhörer müssen
/// sich also nie neu anmelden. Ob ein Wert noch aktuell ist, beurteilt jeder
/// Zuhörer anhand von `Waagenwert.zeit` selbst.
class WaagenDienst {
  final WaagenKanalFabrik kanalFabrik;
  final Future<Uri> Function() adresseLaden;

  /// Feineinstellungen der Verbindung; Tests setzen kurze Zeiten.
  final Duration wiederverbindungsPause;
  final Duration verbindungsTimeout;
  final Duration stilleGrenze;

  final _controller = StreamController<Waagenwert>.broadcast();

  WebSocketWaage? _waage;
  StreamSubscription<Waagenwert>? _abo;
  Uri? _adresse;
  Waagenwert? _letzter;
  bool _laeuft = false;
  int _generation = 0;

  WaagenDienst({
    required this.kanalFabrik,
    required this.adresseLaden,
    this.wiederverbindungsPause = const Duration(seconds: 2),
    this.verbindungsTimeout = const Duration(seconds: 5),
    this.stilleGrenze = const Duration(seconds: 4),
  });

  Stream<Waagenwert> get werte => _controller.stream;

  /// Zuletzt empfangener Messwert (null nach dem Anhalten), damit ein neuer
  /// Zuhörer sofort etwas anzeigen kann. Alt sein darf er nicht: prüfen über `zeit`.
  Waagenwert? get letzter => _letzter;

  bool get laeuft => _laeuft;

  Uri? get adresse => _adresse;

  WaagenVerbindung get verbindung => _waage?.verbindung ?? WaagenVerbindung.getrennt;

  String get statusText => _waage?.statusText ?? 'Waagen-Knoten nicht verbunden';

  /// Öffnet die Verbindung, wenn sie noch nicht läuft (mehrfaches Aufrufen schadet nicht).
  Future<void> starten() async {
    if (_laeuft) return;
    _laeuft = true;
    final generation = ++_generation;
    final Uri adresse;
    try {
      adresse = await adresseLaden();
    } catch (_) {
      // Einstellung nicht lesbar: nicht starten, der nächste Aufruf versucht es erneut.
      if (generation == _generation) _laeuft = false;
      return;
    }
    // Zwischenzeitlich angehalten oder neu gestartet: dieser Start ist überholt.
    if (!_laeuft || generation != _generation) return;

    _adresse = adresse;
    final waage = WebSocketWaage(
      adresse: adresse,
      kanalFabrik: kanalFabrik,
      wiederverbindungsPause: wiederverbindungsPause,
      verbindungsTimeout: verbindungsTimeout,
      stilleGrenze: stilleGrenze,
    );
    _waage = waage;
    _abo = waage.werte.listen((wert) {
      _letzter = wert;
      if (!_controller.isClosed) _controller.add(wert);
    });
    await waage.verbinden();
  }

  /// Schließt die Verbindung (App im Hintergrund). [werte] bleibt bestehen.
  Future<void> anhalten() async {
    _laeuft = false;
    _generation++;
    final abo = _abo;
    final waage = _waage;
    _abo = null;
    _waage = null;
    _letzter = null;
    await abo?.cancel();
    await waage?.trennen();
  }

  /// Verbindet neu, etwa nach einer geänderten Adresse in den Einstellungen.
  Future<void> neuStarten() async {
    await anhalten();
    await starten();
  }
}

/// Gibt die gemeinsame Verbindung als [Waage] weiter, damit die geführte
/// Verwiegung sie wie jede andere Quelle benutzen kann. Schließt oder trennt
/// nie selbst: Die Verbindung gehört der App, nicht dem Bildschirm.
class GeteilteWaage implements Waage {
  final WaagenDienst dienst;

  GeteilteWaage(this.dienst);

  @override
  Stream<Waagenwert> get werte => dienst.werte;

  @override
  String get statusText => dienst.statusText;

  bool get verbunden => dienst.verbindung == WaagenVerbindung.verbunden;

  @override
  Future<void> verbinden() => dienst.starten();

  @override
  Future<void> trennen() async {}
}
