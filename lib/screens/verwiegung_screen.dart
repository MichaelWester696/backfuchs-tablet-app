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
    _sitzungNeuAufbauen();
    setState(() {});
  }

  void _sitzungNeuAufbauen() {
    final plan = VerwiegePlan.erstellen(
      rezept: widget.rezept,
      mengeFuer: widget.mengeFuer,
      stamm: _stamm ?? Rohstoffstamm.leer(),
    );
    _plan = plan;
    _sitzung = VerwiegeSitzung(schritte: plan.schritte);
    _gespeichert = false;
    _protokollId = _neueId();
    final letzter = _letzterWert;
    if (letzter != null) _sitzung!.messwert(letzter);
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

    if (sitzung.phase == SitzungsPhase.fertig && !_gespeichert) {
      _protokollSpeichern(abgebrochen: false);
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

  Future<void> _zurueckFragen() async {
    final sitzung = _sitzung;
    if (sitzung == null || sitzung.phase != SitzungsPhase.laeuft) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final abbrechen = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Verwiegung abbrechen?'),
        content: const Text('Die bisher gewogenen Zutaten bleiben in der Wanne. Wirklich abbrechen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Weiter wiegen')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Abbrechen')),
        ],
      ),
    );
    if (abbrechen != true || !mounted) return;
    sitzung.abbrechen(DateTime.now());
    await _protokollSpeichern(abgebrochen: true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sitzung = _sitzung;
    final laeuft = sitzung?.phase == SitzungsPhase.laeuft;

    return PopScope(
      canPop: !laeuft,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _zurueckFragen();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Verwiegen: ${widget.rezept.name}'),
        ),
        body: sitzung == null
            ? const Center(child: CircularProgressIndicator())
            : _inhalt(sitzung),
      ),
    );
  }

  Widget _inhalt(VerwiegeSitzung sitzung) {
    final Widget haupt;
    switch (sitzung.phase) {
      case SitzungsPhase.vorbereitung:
        haupt = _vorbereitung(sitzung);
        break;
      case SitzungsPhase.laeuft:
        haupt = _laufend(sitzung);
        break;
      case SitzungsPhase.fertig:
      case SitzungsPhase.abgebrochen:
        haupt = _fertig(sitzung);
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
  // Vorbereitung
  // ---------------------------------------------------------------------
  Widget _vorbereitung(VerwiegeSitzung sitzung) {
    final plan = _plan!;
    final jetzt = DateTime.now();
    final bereit = sitzung.kannStarten(jetzt);
    final verbunden = sitzung.verbindungOk(jetzt);

    final String waagenText;
    if (!verbunden) {
      waagenText = 'Keine Verbindung zur Waage';
    } else if (!sitzung.letzter!.stabil) {
      waagenText = 'Waage: ${_kg(sitzung.letzter!.gramm)} (wird ruhig ...)';
    } else {
      waagenText = 'Waage: ${_kg(sitzung.letzter!.gramm)}';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${widget.zielText} · ${plan.schritte.length} Zutaten am Verwiegeplatz',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          '1. Leere Wanne auf die Waage stellen.\n'
          '2. „Start“ drücken.\n'
          '3. Immer nur aus der grün leuchtenden Schütte nehmen.',
          style: TextStyle(fontSize: 20, height: 1.4),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: verbunden ? _farbeRichtig : _farbeZuViel,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(waagenText, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        ),
        if (plan.hinweise.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BackfuchsFarben.gold.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hinweise für die Leitung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                for (final h in plan.hinweise) Text('• $h', style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 64,
          child: ElevatedButton(
            onPressed: bereit
                ? () {
                    sitzung.start(DateTime.now());
                    setState(() {});
                  }
                : null,
            child: const Text('Start – Wanne steht auf der Waage', style: TextStyle(fontSize: 22)),
          ),
        ),
        if (plan.schritte.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Dieses Rezept hat keine Zutaten für den Verwiegeplatz.',
              style: TextStyle(fontSize: 18),
            ),
          ),
        const SizedBox(height: 20),
        const Text('Wird gewogen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
  // Fertig
  // ---------------------------------------------------------------------
  Widget _fertig(VerwiegeSitzung sitzung) {
    final plan = _plan!;
    final abgebrochen = sitzung.phase == SitzungsPhase.abgebrochen;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(
          abgebrochen ? Icons.cancel : Icons.check_circle,
          size: 96,
          color: abgebrochen ? BackfuchsFarben.rot : BackfuchsFarben.gruen,
        ),
        Text(
          abgebrochen ? 'Abgebrochen' : 'Alles gewogen',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        for (final e in sitzung.ergebnisse)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              children: [
                Expanded(child: Text(e.schritt.zutatName, style: const TextStyle(fontSize: 20))),
                Text(
                  e.istG == null
                      ? widget.rezept.formatiereMenge(e.schritt.sollMenge, e.schritt.einheit)
                      : '${_kg(e.istG!)}  (Soll ${_kg(e.schritt.sollG)})',
                  style: const TextStyle(fontSize: 20, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        const Divider(height: 28),
        Text(
          'Summe Soll ${_kg(plan.summeSollG)}',
          style: const TextStyle(fontSize: 18, color: Colors.black54),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 64,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zurück zum Rezept', style: TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(height: 12),
        if (!abgebrochen)
          SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: () {
                _sitzungNeuAufbauen();
                setState(() {});
              },
              child: const Text('Nächster Ansatz', style: TextStyle(fontSize: 20)),
            ),
          ),
      ],
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
