import 'dart:async';

import 'package:backfuchs_produktionsapp/verwiegung/waagen_dienst.dart';
import 'package:backfuchs_produktionsapp/verwiegung/waagen_protokoll.dart';
import 'package:backfuchs_produktionsapp/verwiegung/websocket_waage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kanal zum Ausprobieren: der Test schiebt Nachrichten hinein.
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
}

Future<void> _kurz([int ms = 40]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('WaagenDienst', () {
    late List<_TestKanal> kanaele;
    late List<Uri> adressen;
    late Uri adresse;

    WaagenDienst bauen() {
      kanaele = [];
      adressen = [];
      adresse = Uri.parse('ws://192.168.2.108:81');
      return WaagenDienst(
        kanalFabrik: (a) async {
          adressen.add(a);
          final k = _TestKanal();
          kanaele.add(k);
          return k;
        },
        adresseLaden: () async => adresse,
        wiederverbindungsPause: const Duration(milliseconds: 20),
        verbindungsTimeout: const Duration(milliseconds: 500),
      );
    }

    test('öffnet genau eine Verbindung, auch bei mehrfachem Starten und mehreren Zuhörern', () async {
      final dienst = bauen();
      final a = <Waagenwert>[];
      final b = <Waagenwert>[];
      dienst.werte.listen(a.add);
      dienst.werte.listen(b.add);

      await Future.wait([dienst.starten(), dienst.starten(), dienst.starten()]);
      await _kurz();
      expect(kanaele.length, 1);
      expect(dienst.laeuft, isTrue);
      expect(dienst.verbindung, WaagenVerbindung.verbunden);

      kanaele.single.sende('   0.560 kg    G');
      await _kurz();
      expect(a.length, 1);
      expect(b.length, 1);
      expect(dienst.letzter!.gramm, closeTo(560, 0.001));
      await dienst.anhalten();
    });

    test('Zuhörer, die später kommen oder gehen, ändern an der Verbindung nichts', () async {
      final dienst = bauen();
      await dienst.starten();
      await _kurz();

      final erste = <Waagenwert>[];
      final abo = dienst.werte.listen(erste.add);
      kanaele.single.sende('   1.000 kg    G');
      await _kurz(200); // länger als die Drosselung der Messwerte
      await abo.cancel();

      // "Rezeptwechsel": neuer Zuhörer, die Verbindung bleibt dieselbe.
      expect(dienst.letzter!.gramm, closeTo(1000, 0.001));
      final zweite = <Waagenwert>[];
      dienst.werte.listen(zweite.add);
      kanaele.single.sende('   1.500 kg    G');
      await _kurz();
      expect(kanaele.length, 1);
      expect(kanaele.single.geschlossen, isFalse);
      expect(zweite.single.gramm, closeTo(1500, 0.001));
      await dienst.anhalten();
    });

    test('Anhalten schließt den Kanal, behält den Strom und vergisst den letzten Wert', () async {
      final dienst = bauen();
      final werte = <Waagenwert>[];
      dienst.werte.listen(werte.add);
      await dienst.starten();
      await _kurz();
      kanaele.single.sende('   0.560 kg    G');
      await _kurz();

      await dienst.anhalten();
      await _kurz();
      expect(kanaele.single.geschlossen, isTrue);
      expect(dienst.laeuft, isFalse);
      expect(dienst.letzter, isNull);
      expect(dienst.verbindung, WaagenVerbindung.getrennt);

      // Nach dem Zurückkehren in die App kommen Werte wieder bei denselben Zuhörern an.
      await dienst.starten();
      await _kurz();
      expect(kanaele.length, 2);
      kanaele.last.sende('   0.700 kg    G');
      await _kurz();
      expect(werte.length, 2);
      expect(werte.last.gramm, closeTo(700, 0.001));
      await dienst.anhalten();
    });

    test('Neustart liest die Adresse neu', () async {
      final dienst = bauen();
      await dienst.starten();
      await _kurz();
      adresse = Uri.parse('ws://192.168.2.200:81');
      await dienst.neuStarten();
      await _kurz();
      expect(adressen.map((a) => a.host).toList(), ['192.168.2.108', '192.168.2.200']);
      expect(dienst.adresse!.host, '192.168.2.200');
      await dienst.anhalten();
    });

    test('Anhalten während des Startens verhindert die Verbindung', () async {
      final dienst = bauen();
      final start = dienst.starten();
      await dienst.anhalten();
      await start;
      await _kurz();
      expect(kanaele.length, 0);
      expect(dienst.laeuft, isFalse);
    });

    test('GeteilteWaage trennt die gemeinsame Verbindung nie', () async {
      final dienst = bauen();
      final waage = GeteilteWaage(dienst);
      await waage.verbinden();
      await _kurz();
      expect(waage.verbunden, isTrue);
      await waage.trennen();
      await _kurz();
      expect(kanaele.single.geschlossen, isFalse);
      expect(waage.verbunden, isTrue);
      await dienst.anhalten();
    });
  });
}
