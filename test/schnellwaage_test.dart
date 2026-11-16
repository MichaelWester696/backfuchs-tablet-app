import 'package:backfuchs_produktionsapp/verwiegung/schnellwaage_modell.dart';
import 'package:backfuchs_produktionsapp/verwiegung/waagen_protokoll.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 11, 17, 6, 0, 0);
DateTime _t(int ms) => _t0.add(Duration(milliseconds: ms));

Waagenwert _wert(double gramm, int ms, {bool stabil = true}) =>
    Waagenwert(gramm: gramm, stabil: stabil, zeit: _t(ms));

void main() {
  group('SchnellWaageModell', () {
    test('ohne Messwert gibt es keine Anzeige und Tarieren tut nichts', () {
      final m = SchnellWaageModell();
      expect(m.nettoG(_t(0)), isNull);
      expect(m.tarieren(_t(0)), isFalse);
      expect(m.tariert, isFalse);
    });

    test('zeigt das Gewicht und zieht nach dem Tarieren die Tara ab', () {
      final m = SchnellWaageModell();
      m.neuerWert(_wert(1500, 0));
      expect(m.nettoG(_t(100)), 1500);
      expect(m.tarieren(_t(100)), isTrue);
      expect(m.nettoG(_t(100)), 0);

      m.neuerWert(_wert(2750, 500));
      expect(m.nettoG(_t(600)), 1250);
      expect(m.tariert, isTrue);
      expect(m.taraG, 1500);
    });

    test('ein veralteter Messwert gilt nicht mehr', () {
      final m = SchnellWaageModell();
      m.neuerWert(_wert(1000, 0));
      expect(m.hatAktuellenWert(_t(3000)), isTrue);
      expect(m.hatAktuellenWert(_t(3001)), isFalse);
      expect(m.nettoG(_t(5000)), isNull);
      expect(m.tarieren(_t(5000)), isFalse);
      expect(m.taraG, 0);
    });

    test('Tara löschen zeigt wieder das Bruttogewicht', () {
      final m = SchnellWaageModell();
      m.neuerWert(_wert(1500, 0));
      m.tarieren(_t(10));
      m.taraLoeschen();
      expect(m.tariert, isFalse);
      expect(m.nettoG(_t(20)), 1500);
    });

    test('Stabilität kommt vom letzten Messwert', () {
      final m = SchnellWaageModell();
      m.neuerWert(_wert(1000, 0, stabil: false));
      expect(m.stabil(_t(10)), isFalse);
      m.neuerWert(_wert(1000, 100));
      expect(m.stabil(_t(110)), isTrue);
      expect(m.stabil(_t(9000)), isFalse);
    });

    test('Zurücksetzen vergisst Messwert und Tara', () {
      final m = SchnellWaageModell();
      m.neuerWert(_wert(1500, 0));
      m.tarieren(_t(10));
      m.zuruecksetzen();
      expect(m.letzter, isNull);
      expect(m.tariert, isFalse);
    });

    test('Formatierung mit Komma, drei Stellen und ohne "-0,000"', () {
      expect(SchnellWaageModell.formatiere(140), '0,140 kg');
      expect(SchnellWaageModell.formatiere(1234.4), '1,234 kg');
      expect(SchnellWaageModell.formatiere(0), '0,000 kg');
      expect(SchnellWaageModell.formatiere(-0.2), '0,000 kg');
      expect(SchnellWaageModell.formatiere(-25), '-0,025 kg');
      expect(SchnellWaageModell.formatiere(12000), '12,000 kg');
    });
  });
}
