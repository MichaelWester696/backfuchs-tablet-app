import 'package:backfuchs_produktionsapp/models/rezept.dart';
import 'package:backfuchs_produktionsapp/verwiegung/lampen.dart';
import 'package:backfuchs_produktionsapp/verwiegung/rohstoffstamm.dart';
import 'package:backfuchs_produktionsapp/verwiegung/verwiege_plan.dart';
import 'package:backfuchs_produktionsapp/verwiegung/verwiege_sitzung.dart';
import 'package:backfuchs_produktionsapp/verwiegung/waagen_protokoll.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 29, 6, 0, 0);
DateTime _t(int ms) => _t0.add(Duration(milliseconds: ms));

Waagenwert _w(double gramm, int ms, {bool stabil = true}) =>
    Waagenwert(gramm: gramm, stabil: stabil, zeit: _t(ms));

Verwiegeschritt _schritt(
  String name,
  double sollG, {
  double toleranzG = 10,
  int? position,
  SchrittArt art = SchrittArt.wiegen,
}) {
  return Verwiegeschritt(
    zutatName: name,
    rohstoff: null,
    position: position == null
        ? null
        : Verwiegeposition(nr: position, art: 'schuette', bezeichnung: 'Schütte $position'),
    art: art,
    sollMenge: sollG,
    einheit: art == SchrittArt.wiegen ? 'g' : 'Stück',
    sollG: sollG,
    toleranzG: toleranzG,
  );
}

/// Speist [wert] alle 100 ms von [vonMs] bis [bisMs] ein.
void _halte(VerwiegeSitzung s, double wert, int vonMs, int bisMs, {bool stabil = true}) {
  for (var ms = vonMs; ms <= bisMs; ms += 100) {
    s.messwert(_w(wert, ms, stabil: stabil));
  }
}

void main() {
  group('WaagenProtokoll', () {
    test('liest kg mit Stabilitaet', () {
      final w = WaagenProtokoll.parseZeile('    1.234 kg  G', _t(0))!;
      expect(w.gramm, closeTo(1234, 0.001));
      expect(w.stabil, isTrue);
    });

    test('Fragezeichen heisst instabil', () {
      final w = WaagenProtokoll.parseZeile('  125.5 g ?', _t(0))!;
      expect(w.gramm, closeTo(125.5, 0.001));
      expect(w.stabil, isFalse);
    });

    test('Komma als Dezimaltrenner, negative Werte, ohne Einheit', () {
      expect(WaagenProtokoll.parseZeile('12,5 g', _t(0))!.gramm, closeTo(12.5, 0.001));
      expect(WaagenProtokoll.parseZeile('-0.020 kg N', _t(0))!.gramm, closeTo(-20, 0.001));
      expect(WaagenProtokoll.parseZeile('300', _t(0))!.gramm, closeTo(300, 0.001));
    });

    test('Zeilen ohne Gewicht ergeben null', () {
      expect(WaagenProtokoll.parseZeile('', _t(0)), isNull);
      expect(WaagenProtokoll.parseZeile('Err 8.1', _t(0)), isNull);
    });
  });

  group('Rohstoffstamm', () {
    final stamm = Rohstoffstamm.ausListen(
      rohstoffe: const [
        Rohstoff(id: 'r1', name: 'Salz', typ: RohstoffTyp.verwiegung),
        Rohstoff(id: 'r2', name: 'Roggenmehl', typ: RohstoffTyp.mischer),
        Rohstoff(id: 'r3', name: 'Dinkel Flocken', typ: RohstoffTyp.verwiegung, toleranzProzent: 3, toleranzMinG: 5),
      ],
      aliase: const {'Salz': 'r1', 'Speisesalz': 'r1', 'Roggenmehl': 'r2'},
      positionen: const [
        Verwiegeposition(nr: 1, art: 'schuette', bezeichnung: 'Schütte 1', rohstoffId: 'r1'),
        Verwiegeposition(nr: 2, art: 'schuette', bezeichnung: 'Schütte 2'),
      ],
    );

    test('findet ueber exakten Alias und ueber normalisierten Namen', () {
      expect(stamm.finde('Speisesalz')!.id, 'r1');
      expect(stamm.finde(' Salz ')!.id, 'r1');
      expect(stamm.finde('Flocken Dinkel')!.id, 'r3');
      expect(stamm.finde('Unbekannt'), isNull);
    });

    test('Position wird ueber den Rohstoff gefunden', () {
      expect(stamm.positionFuer(stamm.finde('Salz')!)!.nr, 1);
      expect(stamm.positionFuer(stamm.finde('Roggenmehl')!), isNull);
    });

    test('Toleranz ist das Maximum aus Prozent und Mindestwert', () {
      final r = stamm.finde('Flocken Dinkel')!; // 3 %, mind. 5 g
      expect(r.toleranzFuer(100), closeTo(5, 0.001)); // 3 g < 5 g
      expect(r.toleranzFuer(1000), closeTo(30, 0.001));
    });
  });

  group('VerwiegePlan', () {
    final stamm = Rohstoffstamm.ausListen(
      rohstoffe: const [
        Rohstoff(id: 'r1', name: 'Salz', typ: RohstoffTyp.verwiegung),
        Rohstoff(id: 'r2', name: 'Roggenmehl', typ: RohstoffTyp.mischer),
        Rohstoff(id: 'r3', name: 'Hefe', typ: RohstoffTyp.verwiegung),
        Rohstoff(id: 'r4', name: 'Testmuell', typ: RohstoffTyp.ignorieren),
      ],
      aliase: const {'Salz': 'r1', 'Roggenmehl': 'r2', 'Hefe': 'r3', 'Testmuell': 'r4'},
      positionen: const [
        Verwiegeposition(nr: 5, art: 'schuette', bezeichnung: 'Schütte 5', rohstoffId: 'r1'),
      ],
    );

    final rezept = Rezept(
      id: 'x',
      name: 'Testbrot',
      basisStueckzahl: 10,
      zutaten: [
        Zutat(menge: 20, einheit: 'g', name: 'Salz'),
        Zutat(menge: 5, einheit: 'kg', name: 'Roggenmehl'),
        Zutat(menge: 1.5, einheit: 'kg', name: 'Hefe'),
        Zutat(menge: 2, einheit: 'Stück', name: 'Hefe'),
        Zutat(menge: 3, einheit: 'g', name: 'Testmuell'),
        Zutat(menge: 40, einheit: 'g', name: 'Mystery'),
      ],
      schritte: [],
    );

    test('teilt Zutaten in Wiegen, Zaehlen, anderer Platz und Hinweise', () {
      final plan = VerwiegePlan.erstellen(
        rezept: rezept,
        mengeFuer: (z) => rezept.umgerechneteMenge(z, 20), // Faktor 2
        stamm: stamm,
      );

      expect(plan.schritte.map((s) => s.zutatName).toList(), ['Salz', 'Hefe', 'Hefe', 'Mystery']);
      expect(plan.schritte[0].sollG, closeTo(40, 0.001));
      expect(plan.schritte[0].position!.nr, 5);
      expect(plan.schritte[1].sollG, closeTo(3000, 0.001));
      expect(plan.schritte[2].art, SchrittArt.zaehlen);
      expect(plan.schritte[3].rohstoff, isNull); // unbekannt, wird trotzdem gewogen
      expect(plan.andereZutaten.map((a) => a.name).toList(), ['Roggenmehl']);
      expect(plan.hinweise.length, 2); // Mystery unbekannt, Hefe ohne Lampe (nur einmal genannt)
      expect(plan.summeSollG, closeTo(40 + 3000 + 80, 0.001));
    });
  });

  group('VerwiegePlan ohne Wiegeschritte', () {
    test('meldet einen Hinweis, wenn nichts am Verwiegeplatz zu tun ist', () {
      final rezept = Rezept(
        id: 'y',
        name: 'Nur Mehl',
        basisStueckzahl: 1,
        zutaten: [Zutat(menge: 1, einheit: 'kg', name: 'Roggenmehl')],
        schritte: [],
      );
      final stamm = Rohstoffstamm.ausListen(
        rohstoffe: const [Rohstoff(id: 'r2', name: 'Roggenmehl', typ: RohstoffTyp.mischer)],
        aliase: const {'Roggenmehl': 'r2'},
        positionen: const [],
      );
      final plan = VerwiegePlan.erstellen(rezept: rezept, mengeFuer: (z) => z.menge, stamm: stamm);
      expect(plan.schritte.isEmpty, isTrue);
      expect(plan.hinweise.length, 1);
    });
  });

  group('VerwiegeSitzung', () {
    VerwiegeSitzung neu() => VerwiegeSitzung(schritte: [
          _schritt('Salz', 500, position: 3),
          _schritt('Hefe', 200, toleranzG: 5, position: 7),
        ]);

    test('Start nur mit aktuellem, ruhigem Messwert', () {
      final s = neu();
      expect(s.start(_t(0)), isFalse); // noch kein Wert
      s.messwert(_w(1500, 0, stabil: false));
      expect(s.kannStarten(_t(0)), isFalse); // instabil
      s.messwert(_w(1500, 100));
      expect(s.kannStarten(_t(100)), isTrue);
      expect(s.kannStarten(_t(5000)), isFalse); // Wert veraltet
      expect(s.start(_t(100)), isTrue);
      expect(s.phase, SitzungsPhase.laeuft);
      expect(s.basisG, closeTo(1500, 0.001));
    });

    test('schaltet nach Haltezeit im Fenster weiter und misst relativ zur Wanne', () {
      final s = neu();
      s.messwert(_w(1500, 0));
      s.start(_t(0));

      _halte(s, 1800, 100, 400); // 300 g: zu wenig
      expect(s.zustand(_t(400)), Anzeigezustand.zuWenig);
      expect(s.index, 0);

      _halte(s, 2000, 500, 1500); // 500 g netto: im Fenster, aber Haltezeit noch nicht um
      expect(s.index, 0);
      expect(s.zustand(_t(1500)), Anzeigezustand.imFenster);

      _halte(s, 2000, 1600, 1800); // >= 1,2 s im Fenster
      expect(s.index, 1);
      expect(s.ergebnisse.single.istG, closeTo(500, 0.001));
      expect(s.basisG, closeTo(2000, 0.001));
      expect(s.istG, closeTo(0, 0.001)); // neuer Schritt startet bei 0
    });

    test('Durchlaufen des Fensters ohne Halten bestaetigt nicht', () {
      final s = neu();
      s.messwert(_w(0, 0));
      s.start(_t(0));
      _halte(s, 495, 100, 500); // 400 ms im Fenster
      _halte(s, 700, 600, 800); // weiter drueber hinaus -> zu viel
      expect(s.index, 0);
      expect(s.zustand(_t(800)), Anzeigezustand.zuViel);
    });

    test('instabiler Wert im Fenster bestaetigt nicht', () {
      final s = neu();
      s.messwert(_w(0, 0));
      s.start(_t(0));
      _halte(s, 500, 100, 3000, stabil: false);
      expect(s.index, 0);
      _halte(s, 500, 3100, 4400); // jetzt stabil
      expect(s.index, 1);
    });

    test('bei zu viel wird nicht bestaetigt, nach Herausnehmen schon', () {
      final s = neu();
      s.messwert(_w(0, 0));
      s.start(_t(0));
      _halte(s, 560, 100, 2000);
      expect(s.index, 0);
      expect(s.zustand(_t(2000)), Anzeigezustand.zuViel);
      _halte(s, 505, 2100, 3400);
      expect(s.index, 1);
    });

    test('tick laesst die Haltezeit auch ohne neue Messwerte ablaufen', () {
      final s = neu();
      s.messwert(_w(0, 0));
      s.start(_t(0));
      s.messwert(_w(500, 100)); // Waage sendet nur bei Aenderung
      s.tick(_t(1000));
      expect(s.index, 0);
      s.tick(_t(1400));
      expect(s.index, 1);
    });

    test('tick bestaetigt nicht mehr, wenn die Waage laenger als der Timeout schweigt', () {
      final s = neu();
      s.messwert(_w(0, 0));
      s.start(_t(0));
      s.messwert(_w(500, 100));
      s.tick(_t(3500)); // letzter Wert ist 3,4 s alt -> Verbindung gilt als verloren
      expect(s.index, 0);
      expect(s.zustand(_t(3500)), Anzeigezustand.keineWaage);
    });

    test('sehr kleine Sollmenge bestaetigt nicht bei 0 g', () {
      final s = VerwiegeSitzung(schritte: [_schritt('Gewuerz', 1, toleranzG: 2)]);
      s.messwert(_w(0, 0));
      s.start(_t(0));
      _halte(s, 0, 100, 3000);
      expect(s.index, 0);
      _halte(s, 1, 3100, 4400);
      expect(s.phase, SitzungsPhase.fertig);
    });

    test('Wanne entfernt wird erkannt', () {
      final s = neu();
      s.messwert(_w(1500, 0));
      s.start(_t(0));
      s.messwert(_w(0, 100));
      expect(s.zustand(_t(100)), Anzeigezustand.wanneFehlt);
    });

    test('Verbindungsverlust: keine Waage, Lampen auf Fehler', () {
      final s = neu();
      s.messwert(_w(1500, 0));
      s.start(_t(0));
      expect(s.lampen(_t(500)), LampenAnweisung.nurGruen(3));
      expect(s.zustand(_t(10000)), Anzeigezustand.keineWaage);
      expect(s.lampen(_t(10000)), LampenAnweisung.fehler);
    });

    test('Lampen: Position des aktuellen Schritts, ohne Position alle rot, sonst aus', () {
      final s = VerwiegeSitzung(schritte: [
        _schritt('Salz', 500, position: 3),
        _schritt('Zimt', 20, toleranzG: 2),
      ]);
      expect(s.lampen(_t(0)), LampenAnweisung.aus);
      s.messwert(_w(0, 0));
      s.start(_t(0));
      expect(s.lampen(_t(0)), LampenAnweisung.nurGruen(3));
      _halte(s, 500, 100, 1500);
      expect(s.index, 1);
      expect(s.lampen(_t(1500)), LampenAnweisung.alleRot);
      _halte(s, 520, 1600, 2900);
      expect(s.phase, SitzungsPhase.fertig);
      expect(s.lampen(_t(2900)), LampenAnweisung.aus);
    });

    test('Zaehlschritt nur von Hand, Wiegeschritt nicht von Hand', () {
      final s = VerwiegeSitzung(schritte: [
        _schritt('Salz', 500),
        _schritt('Eier', 3, art: SchrittArt.zaehlen),
      ]);
      s.messwert(_w(0, 0));
      s.start(_t(0));
      expect(s.manuellBestaetigen(_t(100)), isFalse);
      _halte(s, 500, 200, 1500);
      expect(s.index, 1);
      s.messwert(_w(500, 1600));
      expect(s.manuellBestaetigen(_t(1600)), isTrue);
      expect(s.phase, SitzungsPhase.fertig);
      expect(s.ergebnisse.last.istG, isNull);
      expect(s.basisG, closeTo(500, 0.001)); // Zaehlschritt aendert die Tara nicht
    });

    test('Protokoll enthaelt Soll, Ist und Position', () {
      final s = VerwiegeSitzung(schritte: [_schritt('Salz', 500, position: 3)]);
      s.messwert(_w(1500, 0));
      s.start(_t(0));
      _halte(s, 2003, 100, 1400);
      final json = s.ergebnisseAlsJson().single;
      expect(json['zutat'], 'Salz');
      expect(json['position'], 3);
      expect(json['soll_g'], 500);
      expect(json['ist_g'], closeTo(503, 0.001));
      expect(s.phase, SitzungsPhase.fertig);
    });

    test('Abbrechen beendet die Sitzung', () {
      final s = neu();
      s.messwert(_w(0, 0));
      s.start(_t(0));
      s.abbrechen(_t(500));
      expect(s.phase, SitzungsPhase.abgebrochen);
      expect(s.lampen(_t(500)), LampenAnweisung.aus);
    });
  });
}
