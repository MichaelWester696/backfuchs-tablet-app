import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/waagen_einstellungen.dart';
import '../verwiegung/schnellwaage_modell.dart';
import '../verwiegung/waagen_protokoll.dart';
import '../verwiegung/websocket_kanal.dart';
import '../verwiegung/websocket_waage.dart';

/// Leiste am unteren Rand der Rezeptansicht: aktuelles Gewicht der Waage und
/// eine Tara-Taste - zum schnellen Abwiegen zwischendurch. Mehr nicht.
///
/// Im Browser (https) kann die App keine Verbindung ins lokale Netz öffnen,
/// dort erscheint die Leiste nicht. Solange [aktiv] false ist (z.B. während
/// der geführten Verwiegung, die selbst mit der Waage spricht), bleibt die
/// Verbindung getrennt - der Waagen-Knoten bedient nur wenige Tablets gleichzeitig.
/// Adresse des Waagen-Knotens: Einstellung der geführten Verwiegung.
class SchnellWaage extends StatefulWidget {
  final bool aktiv;
  const SchnellWaage({super.key, this.aktiv = true});

  @override
  State<SchnellWaage> createState() => _SchnellWaageState();
}

class _SchnellWaageState extends State<SchnellWaage> {
  final _modell = SchnellWaageModell();
  WebSocketWaage? _waage;
  StreamSubscription<Waagenwert>? _abo;
  Timer? _takt;
  Uri _adresse = Uri.parse(WaagenEinstellungen.standardAdresse);
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    // Frische des Messwerts laufend neu anzeigen.
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
    final adresse = await WaagenEinstellungen.ladeAdresse();
    if (!mounted) return;
    setState(() {
      _adresse = adresse;
      _geladen = true;
    });
    _verbindungAnpassen();
  }

  void _verbindungAnpassen() {
    if (widget.aktiv && _geladen && _waage == null) {
      _starten();
    } else if (!(widget.aktiv && _geladen) && _waage != null) {
      _stoppen();
    }
  }

  void _starten() {
    _modell.zuruecksetzen(); // neue Verbindung: alte Tara passt nicht mehr
    final waage = WebSocketWaage(adresse: _adresse, kanalFabrik: verbindeWebSocket);
    _waage = waage;
    waage.verbinden();
    _abo = waage.werte.listen(_modell.neuerWert);
  }

  void _stoppen() {
    _abo?.cancel();
    _abo = null;
    final waage = _waage;
    _waage = null;
    if (waage != null) unawaited(waage.trennen());
    _modell.zuruecksetzen();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !_geladen) return const SizedBox.shrink();

    final jetzt = DateTime.now();
    final netto = _modell.nettoG(jetzt);
    final stabil = _modell.stabil(jetzt);

    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gewicht: so groß wie die Breite zulässt (bis 130 pt).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  netto == null ? '– – –' : SchnellWaageModell.formatiere(netto),
                  style: TextStyle(
                    fontSize: 130,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: netto == null
                        ? Colors.black38
                        : (stabil ? Colors.black : Colors.black.withValues(alpha: 0.55)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 100),
                  textStyle: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800),
                ),
                onPressed: netto == null ? null : () => setState(() => _modell.tarieren(DateTime.now())),
                child: const Text('Tara'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
