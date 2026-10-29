import 'dart:async';
import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/rezept.dart';
import '../services/verwiegung_service.dart';
import '../theme.dart';
import '../verwiegung/lampen.dart';
import '../verwiegung/rohstoffstamm.dart';
import '../verwiegung/verwiege_plan.dart';
import '../verwiegung/verwiege_sitzung.dart';
import '../verwiegung/waage.dart';
import '../verwiegung/waagen_protokoll.dart';

// Ampelfarben der Verwiegung (hell, damit die große Schrift gut lesbar bleibt).
const _farbeWartet = Color(0xFFE0E0E0);
const _farbeWeniger = Color(0xFFFFE9A8);
const _farbeRichtig = Color(0xFFBFE6BF);
const _farbeZuViel = Color(0xFFF2B8B8);
const _farbeWanne = Color(0xFFFFD2A6);

String _kg(double gramm) => '${(gramm / 1000).toStringAsFixed(3).replaceAll('.', ',')} kg';

/// Geführte Verwiegung eines Rezepts: pro Schritt zeigt die Ansicht die
/// richtige Position (Lampe), die Sollmenge und das Live-Gewicht und schaltet
/// selbst weiter, sobald die Menge stimmt.
class VerwiegungScreen extends StatefulWidget {
  final Rezept rezept;

  /// Auf den Ansatz umgerechnete Menge einer Zutat (wie in der Rezeptanzeige).
  final double Function(Zutat) mengeFuer;

  /// Beschreibung des Ansatzes für das Protokoll, z.B. "120 Stück".
  final String zielText;
  final double? faktor;
  final String? postenId;

  const VerwiegungScreen({
    super.key,
    required this.rezept,
    required this.mengeFuer,
    required this.zielText,
    this.faktor,
    this.postenId,
  });

  @override
  State<VerwiegungScreen> createState() => _VerwiegungScreenState();
}

/// Stationen der geführten Verwiegung.
enum _Ablauf {
  hinweise, // Hinweise an die Leitung, mit OK quittieren
  chargen, // Wie viele Chargen werden gewogen?
  wanne, // Leere Wanne aufstellen -> "Wanne ok" (auch nach jeder fertigen Charge)
  wiegen, // Zutaten wiegen
}

class _VerwiegungScreenState extends State<VerwiegungScreen> {
  // Noch keine echte Waage angebunden: Simulation mit leerer Wanne (1,5 kg).
  final _waage = SimulierteWaage();
  final _lampen = SimulierteLampen();
  final _gewichtController = TextEditingController();
  String _protokollId = _neueId(); // je Ansatz neu, sonst überschriebe der zweite Ansatz den ersten

  StreamSubscription<Waagenwert>? _abo;
  Timer? _takt;

  Rohstoffstamm? _stamm;
  VerwiegePlan? _plan;
  VerwiegeSitzung? _sitzung;
  Waagenwert? _letzterWert;
  bool _gespeichert = false;
  LampenAnweisung _gesendeteLampen = LampenAnweisung.aus;

  _Ablauf _ablauf = _Ablauf.chargen;
  int _chargen = 1; // so viele Chargen sollen gewogen werden
  int _charge = 1; // laufende bzw. zuletzt fertige Charge
  bool _chargeFertig = false; // wahr, sobald die laufende Charge abgeschlossen ist
  double _vorherigesEndeG = 0; // Bruttogewicht am Ende der letzten Charge (volle Wanne)
  double _vorherigesNettoG = 0; // darin enthaltene Zutaten

  @override
  void initState() {
    super.initState();
    _waage.setzeGramm(1500);
    _waage.verbinden();
    _abo = _waage.werte.listen(_neuerWert);
    _takt = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    _laden();
  }

  @override
  void dispose() {
    _takt?.cancel();
    _abo?.cancel();
    _waage.trennen();
    _gewichtController.dispose();
    super.dispose();
  }

  static String _neueId() {
    final zufall = Random().nextInt(0x7fffffff).toRadixString(36);
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$zufall';
  }

  Future<void> _laden() async {
    final stamm = await VerwiegungService.instance.ladeStamm();
    if (!mounted) return;
    _stamm = stamm;
    final plan = VerwiegePlan.erstellen(
      rezept: widget.rezept,
      mengeFuer: widget.mengeFuer,
      stamm: stamm,
    );
    _plan = plan;
    _ablauf = plan.hinweise.isEmpty ? _Ablauf.chargen : _Ablauf.hinweise;
    _neueSitzung();
    setState(() {});
  }

  /// Frische Sitzung für die nächste Charge (gleiche Mengen wie die vorige).
  void _neueSitzung() {
    _sitzung = _frischeSitzung();
    _gespeichert = false;
    _protokollId = _neueId();
  }

  VerwiegeSitzung _frischeSitzung() {
    final sitzung = VerwiegeSitzung(schritte: _plan!.schritte);
    final letzter = _letzterWert;
    if (letzter != null) sitzung.messwert(letzter);
    return sitzung;
  }

  /// Schließt die Wannen-Abfrage ab und startet die Charge. Bei Folgechargen
  /// darf nicht mehr die volle Wanne der vorigen Charge auf der Waage stehen.
  String? _wanneProblem(VerwiegeSitzung sitzung) {
    final jetzt = DateTime.now();
    if (!sitzung.verbindungOk(jetzt)) return 'Keine Verbindung zur Waage';
    if (!sitzung.letzter!.stabil) return 'Waage wird ruhig ...';
    if (_charge > 1 || _chargeFertig) {
      final schwelle = _vorherigesEndeG - _vorherigesNettoG * 0.5;
      if (sitzung.letzter!.gramm > schwelle) {
        return 'Die volle Wanne steht noch auf der Waage – bitte leere Wanne aufstellen';
      }
    }
    return null;
  }

  void _wanneOk() {
    final alt = _sitzung;
    if (alt == null || _wanneProblem(alt) != null) return;
    final folgecharge = _chargeFertig;
    final sitzung = folgecharge ? _frischeSitzung() : alt;
    if (!sitzung.start(DateTime.now())) return;
    setState(() {
      if (folgecharge) {
        _charge++;
        _chargeFertig = false;
        _sitzung = sitzung;
        _gespeichert = false;
        _protokollId = _neueId();
      }
      _ablauf = _Ablauf.wiegen;
    });
  }

  /// Aus dem Hinweis- bzw. Chargen-Schritt weiter zur Wannen-Abfrage.
  void _weiter() {
    setState(() {
      switch (_ablauf) {
        case _Ablauf.hinweise:
          _ablauf = _Ablauf.chargen;
          break;
        case _Ablauf.chargen:
          _charge = 1;
          _chargeFertig = false;
          _ablauf = _Ablauf.wanne;
          break;
        case _Ablauf.wanne:
        case _Ablauf.wiegen:
          break;
      }
    });
  }

  void _neuerWert(Waagenwert wert) {
    _letzterWert = wert;
    _sitzung?.messwert(wert);
    if (mounted) setState(() {});
  }

  void _tick() {
    final sitzung = _sitzung;
    if (sitzung == null || !mounted) return;
    final jetzt = DateTime.now();
    sitzung.tick(jetzt);

    final lampen = sitzung.lampen(jetzt);
    if (lampen != _gesendeteLampen) {
      _gesendeteLampen = lampen;
      _lampen.setze(lampen);
    }

    if (_ablauf == _Ablauf.wiegen && sitzung.phase == SitzungsPhase.fertig && !_gespeichert) {
      _protokollSpeichern(abgebrochen: false);
      _vorherigesEndeG = sitzung.letzter?.gramm ?? 0;
      _vorherigesNettoG = sitzung.ergebnisse.fold(0.0, (summe, e) => summe + (e.istG ?? 0));
      _chargeFertig = true;
      _ablauf = _Ablauf.wanne;
    }
    setState(() {});
  }

  Future<void> _protokollSpeichern({required bool abgebrochen}) async {
    final sitzung = _sitzung;
    if (sitzung == null || sitzung.gestartetAm == null || _gespeichert) return;
    if (abgebrochen && sitzung.ergebnisse.isEmpty) return;
    _gespeichert = true;

    final ende = sitzung.beendetAm ?? DateTime.now();
    await VerwiegungService.instance.speichereProtokoll({
      'id': _protokollId,
      'rezept_id': widget.rezept.id,
      'rezept_name': widget.rezept.name,
      'ziel_text': widget.zielText,
      'faktor': widget.faktor,
      'charge': _charge,
      'chargen_gesamt': _chargen,
      'posten_id': widget.postenId,
      'simuliert': true, // bis die echte Waage angebunden ist
      'abgebrochen': abgebrochen,
      'gestartet_am': sitzung.gestartetAm!.toUtc().toIso8601String(),
      'beendet_am': ende.toUtc().toIso8601String(),
      'start_brutto_g': sitzung.startBruttoG,
      'end_brutto_g': sitzung.letzter?.gramm,
      'schritte': sitzung.ergebnisseAlsJson(),
    });
  }

  /// Während des Wiegens (und zwischen den Chargen einer Serie) wird vor dem
  /// Verlassen nachgefragt, damit nichts versehentlich abgebrochen wird.
  bool get _verlassenMussBestaetigtWerden =>
      _ablauf == _Ablauf.wiegen ||
      (_ablauf == _Ablauf.wanne && _chargeFertig && _charge < _chargen);

  Future<void> _zurueckFragen() async {
    if (!_verlassenMussBestaetigtWerden) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final wiegt = _ablauf == _Ablauf.wiegen;
    final abbrechen = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Verwiegung abbrechen?'),
        content: Text(wiegt
            ? 'Die bisher gewogenen Zutaten bleiben in der Wanne. Wirklich abbrechen?'
            : 'Die weiteren Chargen werden dann nicht gewogen. Wirklich beenden?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Weiter wiegen')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Abbrechen')),
        ],
      ),
    );
    if (abbrechen != true || !mounted) return;
    final sitzung = _sitzung;
    if (wiegt && sitzung != null) {
      sitzung.abbrechen(DateTime.now());
      await _protokollSpeichern(abgebrochen: true);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_verlassenMussBestaetigtWerden,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _zurueckFragen();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Verwiegen: ${widget.rezept.name}'),
        ),
        body: _sitzung == null || _plan == null
            ? const Center(child: CircularProgressIndicator())
            : _inhalt(_sitzung!),
      ),
    );
  }

  Widget _inhalt(VerwiegeSitzung sitzung) {
    final Widget haupt;
    switch (_ablauf) {
      case _Ablauf.hinweise:
        haupt = _hinweiseSeite();
        break;
      case _Ablauf.chargen:
        haupt = _chargenSeite();
        break;
      case _Ablauf.wanne:
        haupt = _wanneSeite(sitzung);
        break;
      case _Ablauf.wiegen:
        haupt = Column(
          children: [
            Container(
              width: double.infinity,
              color: BackfuchsFarben.dunkelrot.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Charge $_charge von $_chargen · ${widget.zielText}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: _laufend(sitzung)),
          ],
        );
        break;
    }

    return Column(
      children: [
        Expanded(child: haupt),
        _simulationsLeiste(),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // 1. Hinweise an die Leitung
  // ---------------------------------------------------------------------
  Widget _hinweiseSeite() {
    final plan = _plan!;
    final nichtsZuWiegen = plan.schritte.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.warning_amber_rounded, size: 80, color: Colors.orange.shade800),
        const Text(
          'Hinweise an die Leitung',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        for (final h in plan.hinweise)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: BackfuchsFarben.gold.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(h, style: const TextStyle(fontSize: 21)),
          ),
        const SizedBox(height: 24),
        SizedBox(
          height: 72,
          child: ElevatedButton(
            onPressed: nichtsZuWiegen ? () => Navigator.of(context).pop() : _weiter,
            child: Text(nichtsZuWiegen ? 'OK – zurück zum Rezept' : 'OK', style: const TextStyle(fontSize: 28)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // 2. Anzahl Chargen
  // ---------------------------------------------------------------------
  Widget _chargenSeite() {
    final plan = _plan!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Wie viele Chargen sollen gewogen werden?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          '1 Charge = ${widget.zielText}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              iconSize: 48,
              onPressed: _chargen > 1 ? () => setState(() => _chargen--) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 150,
              child: Text(
                '$_chargen',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 84, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton.filled(
              iconSize: 48,
              onPressed: _chargen < 30 ? () => setState(() => _chargen++) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (final n in const [1, 2, 3, 4, 5, 6])
              ChoiceChip(
                label: Text('$n', style: const TextStyle(fontSize: 22)),
                selected: _chargen == n,
                onSelected: (_) => setState(() => _chargen = n),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Insgesamt ${_kg(plan.summeSollG * _chargen)} am Verwiegeplatz',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 72,
          child: ElevatedButton(
            onPressed: _weiter,
            child: const Text('Weiter', style: TextStyle(fontSize: 28)),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Wird gewogen (pro Charge)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        for (final s in plan.schritte) _vorschauZeile(s),
        if (plan.andereZutaten.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Nicht am Verwiegeplatz', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final a in plan.andereZutaten)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
              child: Text(
                '${a.name} – ${widget.rezept.formatiereMenge(a.menge, a.einheit)}',
                style: const TextStyle(fontSize: 18, color: Colors.black54),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------
  // 3. Wanne ok (vor der ersten Charge und nach jeder fertigen Charge)
  // ---------------------------------------------------------------------
  Widget _wanneSeite(VerwiegeSitzung sitzung) {
    final folge = _chargeFertig;
    final alleFertig = folge && _charge >= _chargen;
    final problem = alleFertig ? null : _wanneProblem(sitzung);

    final jetzt = DateTime.now();
    final String waagenText;
    if (!sitzung.verbindungOk(jetzt)) {
      waagenText = 'Keine Verbindung zur Waage';
    } else {
      waagenText = 'Waage: ${_kg(sitzung.letzter!.gramm)}${sitzung.letzter!.stabil ? '' : ' (wird ruhig ...)'}';
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (folge)
          const Icon(Icons.check_circle, size: 170, color: BackfuchsFarben.gruen)
        else
          const Icon(Icons.scale, size: 110, color: BackfuchsFarben.dunkelrot),
        const SizedBox(height: 8),
        Text(
          alleFertig
              ? 'Alle Chargen gewogen'
              : (folge ? 'Charge $_charge von $_chargen fertig' : 'Charge 1 von $_chargen'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (alleFertig)
          const Text(
            'Die letzte Wanne kann entnommen werden.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24),
          )
        else
          Text(
            folge
                ? 'Volle Wanne entnehmen und leere Wanne auf die Waage stellen.'
                : 'Leere Wanne auf die Waage stellen.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24),
          ),
        const SizedBox(height: 20),
        if (!alleFertig)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: problem == null ? _farbeRichtig : _farbeWeniger,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              problem ?? waagenText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 20),
        SizedBox(
          height: 84,
          child: ElevatedButton(
            onPressed: alleFertig
                ? () => Navigator.of(context).pop()
                : (problem == null ? _wanneOk : null),
            child: Text(alleFertig ? 'Fertig' : 'Wanne ok', style: const TextStyle(fontSize: 32)),
          ),
        ),
      ],
    );
  }

  Widget _vorschauZeile(Verwiegeschritt s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          _positionsMarke(s, 40),
          const SizedBox(width: 12),
          Expanded(child: Text(s.zutatName, style: const TextStyle(fontSize: 20))),
          Text(
            s.art == SchrittArt.wiegen ? _kg(s.sollG) : widget.rezept.formatiereMenge(s.sollMenge, s.einheit),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionsMarke(Verwiegeschritt s, double groesse) {
    final nr = s.position?.nr;
    return Container(
      width: groesse,
      height: groesse,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: nr == null ? Colors.black12 : BackfuchsFarben.dunkelrot,
        shape: BoxShape.circle,
      ),
      child: Text(
        nr == null ? '–' : '$nr',
        style: TextStyle(
          color: nr == null ? Colors.black54 : Colors.white,
          fontSize: groesse * 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Laufende Verwiegung
  // ---------------------------------------------------------------------
  Widget _laufend(VerwiegeSitzung sitzung) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final breit = constraints.maxWidth >= 760;
        final liste = _schrittListe(sitzung);
        final haupt = _hauptTafel(sitzung);
        if (breit) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: liste),
              Expanded(child: haupt),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(height: 120, child: liste),
            Expanded(child: haupt),
          ],
        );
      },
    );
  }

  Widget _schrittListe(VerwiegeSitzung sitzung) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sitzung.schritte.length,
      itemBuilder: (context, i) {
        final s = sitzung.schritte[i];
        final erledigt = i < sitzung.index;
        final aktiv = i == sitzung.index;
        final ergebnis = erledigt ? sitzung.ergebnisse[i] : null;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: aktiv ? BackfuchsFarben.gold.withValues(alpha: 0.5) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                erledigt ? Icons.check_circle : (aktiv ? Icons.play_circle_fill : Icons.circle_outlined),
                color: erledigt ? BackfuchsFarben.gruen : Colors.black54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.zutatName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: aktiv ? FontWeight.bold : FontWeight.normal,
                    color: erledigt ? Colors.black54 : Colors.black87,
                  ),
                ),
              ),
              Text(
                ergebnis?.istG != null
                    ? _kg(ergebnis!.istG!)
                    : (s.art == SchrittArt.wiegen
                        ? _kg(s.sollG)
                        : widget.rezept.formatiereMenge(s.sollMenge, s.einheit)),
                style: const TextStyle(fontSize: 15, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hauptTafel(VerwiegeSitzung sitzung) {
    final s = sitzung.aktuell;
    if (s == null) return const SizedBox.shrink();
    final jetzt = DateTime.now();
    final zustand = sitzung.zustand(jetzt);

    final positionText = s.position?.bezeichnung ?? 'Keine Lampe zugeordnet';

    Color farbe;
    String meldung;
    switch (zustand) {
      case Anzeigezustand.keineWaage:
        farbe = _farbeWartet;
        meldung = 'Keine Verbindung zur Waage – bitte nicht weiterarbeiten';
        break;
      case Anzeigezustand.wanneFehlt:
        farbe = _farbeWanne;
        meldung = 'Wanne fehlt oder wurde bewegt – bitte Wanne wieder auf die Waage stellen';
        break;
      case Anzeigezustand.zuWenig:
        farbe = _farbeWeniger;
        meldung = s.art == SchrittArt.wiegen ? 'Weiter einfüllen' : 'Bitte abzählen und bestätigen';
        break;
      case Anzeigezustand.imFenster:
        farbe = _farbeRichtig;
        meldung = 'Genau richtig – bitte nicht mehr bewegen';
        break;
      case Anzeigezustand.zuViel:
        farbe = _farbeZuViel;
        meldung = 'Zu viel! Etwas wieder herausnehmen';
        break;
    }

    final ist = sitzung.istG ?? 0;
    final wiegen = s.art == SchrittArt.wiegen;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: farbe, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _positionsMarke(s, 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(positionText, style: const TextStyle(fontSize: 20, color: Colors.black54)),
                    Text(
                      s.zutatName,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            wiegen ? 'Soll: ${_kg(s.sollG)}' : 'Menge: ${widget.rezept.formatiereMenge(s.sollMenge, s.einheit)}',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600),
          ),
          if (wiegen) ...[
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _kg(ist),
                    style: const TextStyle(
                      fontSize: 96,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            _ToleranzBalken(soll: s.sollG, von: s.fensterVonG, bis: s.fensterBisG, ist: ist),
            const SizedBox(height: 6),
            Text(
              'Erlaubt: ${_kg(s.fensterVonG)} – ${_kg(s.fensterBisG)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: sitzung.haltefortschritt(jetzt),
              minHeight: 8,
              backgroundColor: Colors.black12,
              color: BackfuchsFarben.gruen,
            ),
          ] else
            Expanded(
              child: Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(300, 96)),
                  onPressed: () {
                    sitzung.manuellBestaetigen(DateTime.now());
                    setState(() {});
                  },
                  child: const Text('Erledigt', style: TextStyle(fontSize: 30)),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            meldung,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          if (wiegen && sitzung.letzter != null && !sitzung.letzter!.stabil)
            const Text(
              'Waage beruhigt sich ...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Simulation (Waage und Lampen), solange keine echte Hardware angebunden ist
  // ---------------------------------------------------------------------
  Widget _simulationsLeiste() {
    final positionen = _stamm?.positionen ?? const <Verwiegeposition>[];
    return Container(
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Simulation – es ist noch keine Waage angeschlossen',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final d in const [-1000, -100, -10, 10, 100, 1000])
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
                  onPressed: () => _waage.aendere(d.toDouble()),
                  child: Text('${d > 0 ? '+' : '−'}${d.abs() >= 1000 ? '1 kg' : '${d.abs()} g'}'),
                ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _gewichtController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(isDense: true, hintText: 'kg setzen'),
                  onSubmitted: (text) {
                    final kg = double.tryParse(text.replaceAll(',', '.'));
                    if (kg != null) _waage.setzeGramm(kg * 1000);
                  },
                ),
              ),
              FilterChip(
                label: const Text('Verbindung getrennt'),
                selected: _waage.unterbrochen,
                onSelected: (an) => setState(() => _waage.unterbrochen = an),
              ),
            ],
          ),
          if (positionen.isNotEmpty) ...[
            const SizedBox(height: 6),
            _LampenReihe(positionen: positionen, anweisung: _gesendeteLampen),
          ],
        ],
      ),
    );
  }
}

/// Balken von 0 bis 150 % der Sollmenge mit grünem Annahmefenster und Marke für das Ist-Gewicht.
class _ToleranzBalken extends StatelessWidget {
  final double soll;
  final double von;
  final double bis;
  final double ist;

  const _ToleranzBalken({required this.soll, required this.von, required this.bis, required this.ist});

  @override
  Widget build(BuildContext context) {
    final maximal = max(soll * 1.5, bis * 1.05);
    double anteil(double gramm) => (gramm / maximal).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final breite = constraints.maxWidth;
        return SizedBox(
          height: 40,
          child: Stack(
            children: [
              Positioned.fill(
                top: 12,
                bottom: 12,
                child: Container(
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                ),
              ),
              Positioned(
                left: breite * anteil(von),
                width: breite * (anteil(bis) - anteil(von)),
                top: 8,
                bottom: 8,
                child: Container(
                  decoration: BoxDecoration(color: BackfuchsFarben.gruen, borderRadius: BorderRadius.circular(6)),
                ),
              ),
              Positioned(
                left: (breite * anteil(ist) - 3).clamp(0.0, max(0.0, breite - 6)),
                width: 6,
                top: 0,
                bottom: 0,
                child: Container(color: Colors.black87),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Bildschirmabbild des LED-Streifens am Schütten-Regal.
class _LampenReihe extends StatelessWidget {
  final List<Verwiegeposition> positionen;
  final LampenAnweisung anweisung;

  const _LampenReihe({required this.positionen, required this.anweisung});

  @override
  Widget build(BuildContext context) {
    // Beim Fehler blinkt alles rot (Takt aus der Systemzeit, der Bildschirm
    // wird ohnehin alle 200 ms neu gezeichnet).
    final blinkAus = anweisung.modus == LampenModus.fehler && DateTime.now().millisecond >= 500;

    Color farbeFuer(Verwiegeposition p) {
      switch (anweisung.modus) {
        case LampenModus.aus:
          return Colors.black26;
        case LampenModus.alleRot:
          return Colors.red.shade700;
        case LampenModus.einsGruen:
          return p.nr == anweisung.position ? Colors.green.shade600 : Colors.red.shade700;
        case LampenModus.fehler:
          return blinkAus ? Colors.black26 : Colors.red.shade700;
      }
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final p in positionen)
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: farbeFuer(p), shape: BoxShape.circle),
            child: Text('${p.nr}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
