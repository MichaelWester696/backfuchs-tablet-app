import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/waagen_verbindung.dart';
import '../verwiegung/schnellwaage_modell.dart';
import '../verwiegung/waagen_protokoll.dart';

/// Leiste am unteren Rand der Rezeptansicht: aktuelles Gewicht der Waage und
/// eine Tara-Taste - zum schnellen Abwiegen zwischendurch. Mehr nicht.
///
/// Die Leiste öffnet keine eigene Verbindung, sondern hört an der gemeinsamen
/// Verbindung der App zum Waagen-Knoten mit ([waagenDienst]). Deshalb steht
/// das Gewicht auch nach einem Rezeptwechsel sofort da. Im Browser (https) kann
/// die App keine Verbindung ins lokale Netz öffnen, dort erscheint die Leiste
/// nicht. Die Adresse des Waagen-Knotens ist eine Einstellung der geführten
/// Verwiegung.
class SchnellWaage extends StatefulWidget {
  const SchnellWaage({super.key});

  @override
  State<SchnellWaage> createState() => _SchnellWaageState();
}

class _SchnellWaageState extends State<SchnellWaage> {
  // Die Tara gilt nur für dieses Rezept: ein Rezeptwechsel beginnt wieder bei
  // null, damit keine vergessene Tara einer anderen Schüssel das Gewicht verfälscht.
  final _modell = SchnellWaageModell();
  StreamSubscription<Waagenwert>? _abo;
  Timer? _takt;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    final letzter = waagenDienst.letzter;
    if (letzter != null) _modell.neuerWert(letzter); // sofort anzeigen, falls frisch
    _abo = waagenDienst.werte.listen(_modell.neuerWert);
    // Frische des Messwerts laufend neu anzeigen.
    _takt = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _takt?.cancel();
    _abo?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

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
