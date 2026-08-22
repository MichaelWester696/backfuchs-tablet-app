import 'package:flutter/material.dart';

import '../models/rezept.dart';

enum _Skalierungsmodus { stueckzahl, gewicht }

class RezeptDetailScreen extends StatefulWidget {
  final Rezept rezept;
  const RezeptDetailScreen({super.key, required this.rezept});

  @override
  State<RezeptDetailScreen> createState() => _RezeptDetailScreenState();
}

class _RezeptDetailScreenState extends State<RezeptDetailScreen> {
  _Skalierungsmodus _modus = _Skalierungsmodus.stueckzahl;

  late int _zielStueckzahl;
  late TextEditingController _stueckzahlController;

  late double _zielGewichtKg;
  late TextEditingController _gewichtController;

  @override
  void initState() {
    super.initState();
    _zielStueckzahl = widget.rezept.basisStueckzahl;
    _stueckzahlController = TextEditingController(text: _zielStueckzahl.toString());

    _zielGewichtKg = widget.rezept.basisGewichtKg;
    _gewichtController = TextEditingController(text: _formatKg(_zielGewichtKg));
  }

  @override
  void dispose() {
    _stueckzahlController.dispose();
    _gewichtController.dispose();
    super.dispose();
  }

  String _formatKg(double kg) {
    final gerundet = (kg * 100).round() / 100;
    return gerundet == gerundet.roundToDouble() ? gerundet.toStringAsFixed(0) : gerundet.toString();
  }

  void _stueckzahlAktualisieren(String value) {
    final n = int.tryParse(value);
    if (n != null && n > 0) {
      setState(() => _zielStueckzahl = n);
    }
  }

  void _gewichtAktualisieren(String value) {
    final n = double.tryParse(value.replaceAll(',', '.'));
    if (n != null && n > 0) {
      setState(() => _zielGewichtKg = n);
    }
  }

  double _mengeFuer(Zutat z) {
    final r = widget.rezept;
    return _modus == _Skalierungsmodus.stueckzahl
        ? r.umgerechneteMenge(z, _zielStueckzahl)
        : r.umgerechneteMengeNachGewicht(z, _zielGewichtKg);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rezept;
    final gewichtVerfuegbar = r.basisGewichtKg > 0;

    return Scaffold(
      appBar: AppBar(title: Text(r.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_Skalierungsmodus>(
            segments: const [
              ButtonSegment(value: _Skalierungsmodus.stueckzahl, label: Text('Nach Stückzahl'), icon: Icon(Icons.numbers)),
              ButtonSegment(value: _Skalierungsmodus.gewicht, label: Text('Nach Gewicht (kg)'), icon: Icon(Icons.scale)),
            ],
            selected: {_modus},
            onSelectionChanged: gewichtVerfuegbar
                ? (auswahl) => setState(() => _modus = auswahl.first)
                : null,
          ),
          if (!gewichtVerfuegbar)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Gewichts-Skalierung nicht möglich: Für dieses Rezept sind keine Zutaten in g/kg hinterlegt.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 16),
          if (_modus == _Skalierungsmodus.stueckzahl)
            Row(
              children: [
                const Text('Zielstückzahl:', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _stueckzahlController,
                    keyboardType: TextInputType.number,
                    onChanged: _stueckzahlAktualisieren,
                    style: const TextStyle(fontSize: 22),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Text('(Basis: ${r.basisStueckzahl})', style: const TextStyle(color: Colors.black54)),
              ],
            )
          else
            Row(
              children: [
                const Text('Zielgewicht (kg):', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _gewichtController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: _gewichtAktualisieren,
                    style: const TextStyle(fontSize: 22),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Text('(Basis: ${_formatKg(r.basisGewichtKg)} kg)', style: const TextStyle(color: Colors.black54)),
              ],
            ),
          const Divider(height: 32),
          const Text('Zutaten', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...r.zutaten.map((z) {
            final menge = _mengeFuer(z);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(z.name, style: const TextStyle(fontSize: 18))),
                  Text(
                    r.formatiereMenge(menge, z.einheit),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
          const Divider(height: 32),
          const Text('Arbeitsschritte', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...r.schritte.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final schritt = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$index. ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      schritt.text,
                      style: TextStyle(fontSize: 18, fontStyle: schritt.fix ? FontStyle.italic : FontStyle.normal),
                    ),
                  ),
                  if (schritt.fix)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Tooltip(message: 'Wird nicht skaliert (z.B. Temperatur/Zeit)', child: Icon(Icons.lock, size: 18)),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
