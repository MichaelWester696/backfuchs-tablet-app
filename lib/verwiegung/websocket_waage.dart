import 'dart:async';

import 'waage.dart';
import 'waagen_nachrichten.dart';
import 'waagen_protokoll.dart';

/// Eine geöffnete Verbindung zum Waagen-Knoten (Textnachrichten).
abstract class WaagenKanal {
  Stream<String> get nachrichten;
  Future<void> schliessen();
}

/// Öffnet die Verbindung. Die echte Umsetzung steht in `websocket_kanal.dart`,
/// Tests übergeben eine eigene.
typedef WaagenKanalFabrik = Future<WaagenKanal> Function(Uri adresse);

enum WaagenVerbindung { getrennt, verbindet, verbunden }

/// Echte Waage: liest die Zeilen des Waagen-Knotens (ESP32) per WebSocket.
///
/// Reißt die Verbindung ab oder kommt länger als [stilleGrenze] gar nichts vom
/// Knoten (er schickt jede Sekunde einen Herzschlag), wird neu verbunden. Ob
/// die Waage selbst noch Werte liefert, beurteilt die Verwiegesitzung anhand
/// der Zeitstempel der Messwerte - hier geht es nur um die Verbindung.
class WebSocketWaage implements Waage {
  final Uri adresse;
  final WaagenKanalFabrik kanalFabrik;
  final Duration wiederverbindungsPause;
  final Duration verbindungsTimeout;
  final Duration stilleGrenze;

  /// So oft wird geprüft, ob der Knoten noch etwas schickt.
  final Duration pruefTakt;
  final DateTime Function() jetzt;

  final _controller = StreamController<Waagenwert>.broadcast();
  final WaagenNachrichten _auswertung;

  WaagenVerbindung _verbindung = WaagenVerbindung.getrennt;
  bool _beendet = false;
  bool _laeuft = false;
  DateTime _letzteNachricht = DateTime.fromMillisecondsSinceEpoch(0);
  Completer<void>? _abbruch;

  WebSocketWaage({
    required this.adresse,
    required this.kanalFabrik,
    this.wiederverbindungsPause = const Duration(seconds: 2),
    this.verbindungsTimeout = const Duration(seconds: 5),
    this.stilleGrenze = const Duration(seconds: 4),
    this.pruefTakt = const Duration(milliseconds: 500),
    DateTime Function()? jetzt,
    WaagenNachrichten? auswertung,
  })  : jetzt = jetzt ?? DateTime.now,
        _auswertung = auswertung ?? WaagenNachrichten();

  @override
  Stream<Waagenwert> get werte => _controller.stream;

  WaagenVerbindung get verbindung => _verbindung;

  /// Letzter Herzschlag des Knotens (null, solange noch keiner kam).
  KnotenHerzschlag? get herzschlag => _auswertung.herzschlag;

  int get verworfeneZeilen => _auswertung.verworfeneZeilen;

  @override
  String get statusText {
    switch (_verbindung) {
      case WaagenVerbindung.verbunden:
        return 'Waagen-Knoten verbunden';
      case WaagenVerbindung.verbindet:
        return 'Verbinde mit Waagen-Knoten ...';
      case WaagenVerbindung.getrennt:
        return 'Waagen-Knoten nicht erreichbar';
    }
  }

  @override
  Future<void> verbinden() async {
    if (_laeuft || _beendet) return;
    _laeuft = true;
    unawaited(_lauf());
  }

  @override
  Future<void> trennen() async {
    _beendet = true;
    final abbruch = _abbruch;
    if (abbruch != null && !abbruch.isCompleted) abbruch.complete();
    await _controller.close();
  }

  Future<void> _lauf() async {
    while (!_beendet) {
      WaagenKanal? kanal;
      try {
        _verbindung = WaagenVerbindung.verbindet;
        kanal = await kanalFabrik(adresse).timeout(verbindungsTimeout);
        if (_beendet) break;

        _verbindung = WaagenVerbindung.verbunden;
        _letzteNachricht = jetzt();
        final ende = Completer<void>();
        _abbruch = ende;
        void beenden() {
          if (!ende.isCompleted) ende.complete();
        }

        final abo = kanal.nachrichten.listen(
          _empfange,
          onError: (Object _) => beenden(),
          onDone: beenden,
          cancelOnError: true,
        );
        final wache = Timer.periodic(pruefTakt, (_) {
          if (jetzt().difference(_letzteNachricht) > stilleGrenze) beenden();
        });
        await ende.future;
        wache.cancel();
        await abo.cancel();
      } catch (_) {
        // Verbindung fehlgeschlagen oder abgerissen: unten nach kurzer Pause neu versuchen.
      } finally {
        _verbindung = WaagenVerbindung.getrennt;
        try {
          await kanal?.schliessen();
        } catch (_) {}
      }
      if (_beendet) break;
      await Future<void>.delayed(wiederverbindungsPause);
    }
  }

  void _empfange(String nachricht) {
    final jetztZeit = jetzt();
    _letzteNachricht = jetztZeit;
    final wert = _auswertung.verarbeite(nachricht, jetztZeit);
    if (wert != null && !_controller.isClosed) _controller.add(wert);
  }
}
