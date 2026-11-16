import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/waagen_einstellungen.dart';
import '../theme.dart';
import '../verwiegung/schnellwaage_modell.dart';
import '../verwiegung/waage.dart';
import '../verwiegung/waagen_protokoll.dart';
import '../verwiegung/websocket_kanal.dart';
import '../verwiegung/websocket_waage.dart';

/// Leiste am unteren Rand der Rezeptansicht: zeigt das aktuelle Gewicht der
/// Waage und tariert auf Knopfdruck - zum schnellen Abwiegen zwischendurch.
///
/// Im Browser (https) kann die App keine Verbindung ins lokale Netz öffnen,
/// dort erscheint die Leiste nicht. Solange [aktiv] false ist (z.B. während
/// der geführten Verwiegung, die selbst mit der Waage spricht), bleibt die
/// Verbindung getrennt - der Waagen-Knoten bedient nur wenige Tablets gleichzeitig.
class SchnellWaage extends StatefulWidget {
  final bool aktiv;
  const SchnellWaage({super.key, this.aktiv = true});

  @override
  State<SchnellWaage> createState() => _SchnellWaageState();
}

class _SchnellWaageState extends State<SchnellWaage> {
  final _modell = SchnellWaageModell();
  Waage? _waage;
  SimulierteWaage? _simulation;
  StreamSubscription<Waagenwert>? _abo;
  Timer? _takt;

  Uri _adresse = Uri.parse(WaagenEinstellungen.standardAdresse);
  bool _simulationAn = false;
  bool _ausgeklappt = true;
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    // Frische des Messwerts und Verbindungsstatus laufend neu anzeigen.
    _takt = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _waage != null) setState(() {});
    });
    _laden();
  }

  @override
  void didUpdateWidget(SchnellWaage alt) {
    super.didUpdateWidget(alt);
    if (alt.aktiv != widget.aktiv) _verbindungAnpassen();
  }

  @override
  void dispose() {
    _takt?.cancel();
    _stoppen();
    super.dispose();
  }

  Future<void> _laden() async {
    final ausgeklappt = await WaagenEinstellungen.ladeSchnellwaage();
    final adresse = await WaagenEinstellungen.ladeAdresse();
    final simulation = await WaagenEinstellungen.ladeSimulation(standard: false);
    if (!mounted) return;
    setState(() {
      _ausgeklappt = ausgeklappt;
      _adresse = adresse;
      _simulationAn = simulation;
      _geladen = true;
    });
    _verbindungAnpassen();
  }

  /// Verbindet nur, solange die Leiste sichtbar und aktiv ist.
  void _verbindungAnpassen() {
    final soll = widget.aktiv && _ausgeklappt && _geladen;
    if (soll && _waage == null) {
      _starten();
    } else if (!soll && _waage != null) {
      _stoppen();
    }
  }

  void _starten() {
    _modell.zuruecksetzen(); // neue Verbindung: alte Tara passt nicht mehr
    final Waage waage;
    if (_simulationAn) {
      final sim = SimulierteWaage();
      _simulation = sim;
      waage = sim;
    } else {
      _simulation = null;
      waage = WebSocketWaage(adresse: _adresse, kanalFabrik: verbindeWebSocket);
    }
    _waage = waage;
    waage.verbinden();
    _abo = waage.werte.listen(_modell.neuerWert);
  }

  void _stoppen() {
    _abo?.cancel();
    _abo = null;
    final waage = _waage;
    _waage = null;
    _simulation = null;
    if (waage != null) unawaited(waage.trennen());
    _modell.zuruecksetzen();
  }

  Future<void> _ausklappen(bool an) async {
    setState(() => _ausgeklappt = an);
    _verbindungAnpassen();
    try {
      await WaagenEinstellungen.speichereSchnellwaage(an);
    } catch (_) {}
  }

  Future<void> _einstellungenOeffnen() async {
    final adresseController = TextEditingController(text: _adresse.toString());
    var simulation = _simulationAn;
    String? fehler;
    final uebernommen = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Waage'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: adresseController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Adresse des Waagen-Knotens',
                  helperText: 'z. B. ws://192.168.2.108:81',
                  errorText: fehler,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Simulation statt echter Waage'),
                subtitle: const Text('Nur zum Ausprobieren.'),
                value: simulation,
                onChanged: (an) => setDialog(() => simulation = an),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
            TextButton(
              onPressed: () {
                if (WaagenEinstellungen.pruefeAdresse(adresseController.text) == null) {
                  setDialog(() => fehler = 'Ungültige Adresse');
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Übernehmen'),
            ),
          ],
        ),
      ),
    );
    final adresse = WaagenEinstellungen.pruefeAdresse(adresseController.text);
    adresseController.dispose();
    if (uebernommen != true || adresse == null || !mounted) return;
    await WaagenEinstellungen.speichereAdresse(adresse);
    await WaagenEinstellungen.speichereSimulation(simulation);
    if (!mounted) return;
    _adresse = adresse;
    _simulationAn = simulation;
    _stoppen();
    _verbindungAnpassen();
    setState(() {});
  }

  String _statusText() {
    final waage = _waage;
    if (waage == null) return 'Waage wird gestartet ...';
    if (_simulation != null) return 'Simulation';
    if (waage is WebSocketWaage && waage.verbindung == WaagenVerbindung.verbunden) {
      return 'Waagen-Knoten verbunden, aber die Waage sendet nichts';
    }
    return waage.statusText;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !_geladen) return const SizedBox.shrink();
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: _ausgeklappt ? _leiste() : _eingeklappt(),
      ),
    );
  }

  Widget _eingeklappt() {
    return InkWell(
      onTap: () => _ausklappen(true),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.scale, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Waage anzeigen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            Icon(Icons.keyboard_arrow_up),
          ],
        ),
      ),
    );
  }

  Widget _leiste() {
    final jetzt = DateTime.now();
    final netto = _modell.nettoG(jetzt);
    final stabil = _modell.stabil(jetzt);
    final sim = _simulation;

    final String gewicht = netto == null ? '– – –' : SchnellWaageModell.formatiere(netto);
    final String zeile2 = netto == null
        ? _statusText()
        : _modell.tariert
            ? 'Tara ${SchnellWaageModell.formatiere(_modell.taraG)} abgezogen'
            : (stabil ? 'stabil' : 'unruhig');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.scale, size: 22, color: netto == null ? Colors.red.shade800 : BackfuchsFarben.gruen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        gewicht,
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: netto == null
                              ? Colors.black38
                              : (stabil ? Colors.black : Colors.black.withValues(alpha: 0.55)),
                        ),
                      ),
                    ),
                    Text(
                      zeile2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: netto == null ? Colors.red.shade800 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (_modell.tariert)
                IconButton(
                  tooltip: 'Tara löschen',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () => setState(_modell.taraLoeschen),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 56),
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                onPressed: netto == null ? null : () => setState(() => _modell.tarieren(DateTime.now())),
                icon: const Icon(Icons.exposure_zero),
                label: const Text('Tara'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Mehr',
                onSelected: (wert) {
                  if (wert == 'einstellungen') _einstellungenOeffnen();
                  if (wert == 'ausblenden') _ausklappen(false);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'einstellungen', child: Text('Waage einstellen')),
                  PopupMenuItem(value: 'ausblenden', child: Text('Waage ausblenden')),
                ],
              ),
            ],
          ),
          if (sim != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final d in const [-1000, -100, 100, 1000])
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36)),
                      onPressed: () => sim.aendere(d.toDouble()),
                      child: Text('${d > 0 ? '+' : '−'}${d.abs() >= 1000 ? '1 kg' : '${d.abs()} g'}'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
