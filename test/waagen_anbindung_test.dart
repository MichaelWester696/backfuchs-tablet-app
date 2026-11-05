import 'dart:async';

import 'package:backfuchs_produktionsapp/verwiegung/waagen_nachrichten.dart';
import 'package:backfuchs_produktionsapp/verwiegung/waagen_protokoll.dart';
import 'package:backfuchs_produktionsapp/verwiegung/websocket_waage.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 11, 5, 6, 0, 0);
DateTime _t(int ms) => _t0.add(Duration(milliseconds: ms));

/// Kanal zum Ausprobieren: der Test schiebt Nachrichten hinein und beendet ihn.
class _TestKanal implements WaagenKanal {
  final _controller = StreamController<String>();
  bool geschlossen = false;

  @override
  Stream<String> get nachrichten => _controller.stream;

  @override
  Future<void> schliessen() async {
    geschlossen = true;
    if (!_controller.isClosed) await _controller.close();
  }

  void sende(String text) => _controller.add(text);
  Future<void> beende() => _controller.close();
}

void main() {
  group('WaagenNachrichten', () {
    test('Gewichtszeile ergibt einen Messwert, Herzschlag und Meldungen nicht', () {
      final n = WaagenNachrichten();
      expect(n.verarbeite('#hello waagen-knoten', _t(0)), isNull);
      expect(n.verarbeite('#hb 12 -1 0 5 0 3', _t(10)), isNull);
      final w = n.verarbeite('   0.140 kg    G', _t(20))!;
      expect(w.gramm, closeTo(140, 0.001));
      expect(w.stabil, isTrue);
    });

    test('Werte werden gedrosselt, ein Wechsel stabil/instabil geht sofort durch', () {
      final n = WaagenNachrichten(mindestAbstand: const Duration(milliseconds: 100));
      expect(n.verarbeite('   0.140 kg    G', _t(0)), isNotNull);
      expect(n.verarbeite('   0.140 kg    G', _t(20)), isNull);
      expect(n.verarbeite('   0.140 kg    G', _t(99)), isNull);
      expect(n.verarbeite('   0.140 kg    G', _t(100)), isNotNull);
      // Wechsel auf instabil innerhalb der Sperrzeit wird trotzdem gemeldet.
      final instabil = n.verarbeite('   0.145 kg   ?G', _t(110))!;
      expect(instabil.stabil, isFalse);
      expect(n.verarbeite('   0.145 kg   ?G', _t(120)), isNull);
      expect(n.verarbeite('   0.145 kg    G', _t(130))!.stabil, isTrue);
    });

    test('Stoerzeilen werden gezaehlt und verworfen', () {
      final n = WaagenNachrichten();
      expect(n.verarbeite('   0.0\u0013Z   G', _t(0)), isNull);
      expect(n.verarbeite('kg    G', _t(10)), isNull);
      expect(n.verarbeite('   0.025       G', _t(20)), isNull); // Einheit fehlt
      expect(n.verworfeneZeilen, 3);
    });

    test('Herzschlag wird ausgewertet', () {
      final n = WaagenNachrichten();
      expect(n.herzschlag, isNull);
      n.verarbeite('#hb 2224 45376 5 1825166 21 780139', _t(0));
      expect(n.herzschlag!.betriebsSekunden, 2224);
      expect(n.herzschlag!.msSeitLetzterZeile, 45376);
      expect(n.herzschlag!.verworfeneZeilen, 5);
      n.verarbeite('#hb 2225 -1 5', _t(1000));
      expect(n.herzschlag!.msSeitLetzterZeile, isNull);
      // Unvollständige Herzschläge werden ignoriert.
      n.verarbeite('#hb 2226', _t(2000));
      expect(n.herzschlag!.betriebsSekunden, 2225);
    });
  });

  group('WebSocketWaage', () {
    WebSocketWaage bauen(WaagenKanalFabrik fabrik, {Duration stille = const Duration(seconds: 4)}) {
      return WebSocketWaage(
        adresse: Uri.parse('ws://192.168.2.108:81'),
        kanalFabrik: fabrik,
        wiederverbindungsPause: const Duration(milliseconds: 40),
        verbindungsTimeout: const Duration(milliseconds: 500),
        stilleGrenze: stille,
        pruefTakt: const Duration(milliseconds: 20),
        auswertung: WaagenNachrichten(mindestAbstand: Duration.zero),
      );
    }

    test('liefert Messwerte und meldet verbunden', () async {
      final kanal = _TestKanal();
      final waage = bauen((_) async => kanal);
      final werte = <Waagenwert>[];
      waage.werte.listen(werte.add);
      expect(waage.verbindung, WaagenVerbindung.getrennt);

      await waage.verbinden();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(waage.verbindung, WaagenVerbindung.verbunden);
      kanal.sende('#hb 1 -1 0 0 0 0');
      kanal.sende('   0.560 kg    G');
      kanal.sende('   0.565 kg   ?G');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(werte.length, 2);
      expect(werte[0].gramm, closeTo(560, 0.001));
      expect(werte[1].stabil, isFalse);
      expect(waage.herzschlag!.betriebsSekunden, 1);
      await waage.trennen();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(kanal.geschlossen, isTrue);
    });

    test('verbindet nach Abbruch der Verbindung neu', () async {
      final kanaele = <_TestKanal>[];
      final waage = bauen((_) async {
        final k = _TestKanal();
        kanaele.add(k);
        return k;
      });
      final werte = <Waagenwert>[];
      waage.werte.listen(werte.add);
      await waage.verbinden();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      kanaele[0].sende('   1.000 kg    G');
      await kanaele[0].beende();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(kanaele.length >= 2, isTrue);
      kanaele[1].sende('   2.000 kg    G');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(werte.map((w) => w.gramm).toList(), [1000.0, 2000.0]);
      await waage.trennen();
    });

    test('versucht es nach fehlgeschlagener Verbindung erneut', () async {
      var versuche = 0;
      final waage = bauen((_) async {
        versuche++;
        if (versuche < 3) throw StateError('nicht erreichbar');
        return _TestKanal();
      });
      await waage.verbinden();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(waage.verbindung == WaagenVerbindung.getrennt || waage.verbindung == WaagenVerbindung.verbindet, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(versuche, 3);
      expect(waage.verbindung, WaagenVerbindung.verbunden);
      await waage.trennen();
    });

    test('ein stiller Knoten fuehrt zu einer neuen Verbindung', () async {
      var versuche = 0;
      final waage = bauen((_) async {
        versuche++;
        return _TestKanal(); // schickt nie etwas
      }, stille: const Duration(milliseconds: 100));
      await waage.verbinden();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(versuche >= 2, isTrue);
      await waage.trennen();
    });
  });
}
