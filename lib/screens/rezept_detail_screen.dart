import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Lässt Mitarbeiter die Zutaten-/Schritte-Schrift am Tablet nach Bedarf
  // größer oder kleiner stellen (z.B. bei größerem Abstand zum Bildschirm).
  // Wird pro Gerät in SharedPreferences gemerkt, damit die Einstellung nicht
  // bei jedem Rezeptaufruf neu gewählt werden muss.
  static const double _schriftMin = 0.7;
  static const double _schriftMax = 1.8;
  static const String _schriftPrefsKey = 'rezept_schrift_skalierung';
  double _schriftSkalierung = 1.0;

  Future<void> _schriftSkalierungLaden() async {
    final prefs = await SharedPreferences.getInstance();
    final gespeichert = prefs.getDouble(_schriftPrefsKey);
    if (gespeichert != null && mounted) {
      setState(() => _schriftSkalierung = gespeichert.clamp(_schriftMin, _schriftMax));
    }
  }

  Future<void> _schriftSkalierungSpeichern() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_schriftPrefsKey, _schriftSkalierung);
  }

  void _schriftVerkleinern() {
    setState(() => _schriftSkalierung = (_schriftSkalierung - 0.1).clamp(_schriftMin, _schriftMax));
    _schriftSkalierungSpeichern();
  }

  void _schriftVergroessern() {
    setState(() => _schriftSkalierung = (_schriftSkalierung + 0.1).clamp(_schriftMin, _schriftMax));
    _schriftSkalierungSpeichern();
  }

  @override
  void initState() {
    super.initState();
    _zielStueckzahl = widget.rezept.basisStueckzahl;
    _stueckzahlController = TextEditingController(text: _zielStueckzahl.toString());

    _zielGewichtKg = widget.rezept.basisGewichtKg;
    _gewichtController = TextEditingController(text: _formatKg(_zielGewichtKg));

    _schriftSkalierungLaden();
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

  /// Gewichtsbasierte Zutaten (g/kg) werden immer einheitlich in kg mit
  /// genau drei Nachkommastellen angezeigt (z.B. "1,100 kg"), damit die
  /// Kommas in der Spalte untereinander stehen. Andere Einheiten (Stück,
  /// TL, EL, l, ml) behalten die bestehende Formatierung.
  String _formatiereMengeLinks(double menge, String einheit) {
    if (einheit == 'g' || einheit == 'kg') {
      final kg = einheit == 'g' ? menge / 1000 : menge;
      return '${kg.toStringAsFixed(3).replaceAll('.', ',')} kg';
    }
    return widget.rezept.formatiereMenge(menge, einheit);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rezept;
    final gewichtVerfuegbar = r.basisGewichtKg > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(r.name),
        actions: [
          IconButton(
            tooltip: 'Schrift verkleinern',
            icon: const Icon(Icons.zoom_out),
            onPressed: _schriftSkalierung > _schriftMin ? _schriftVerkleinern : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('${(_schriftSkalierung * 100).round()}%', style: const TextStyle(fontSize: 14)),
          ),
          IconButton(
            tooltip: 'Schrift vergrößern',
            icon: const Icon(Icons.zoom_in),
            onPressed: _schriftSkalierung < _schriftMax ? _schriftVergroessern : null,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Kompakte Kopfzeile: Umschalter und Zieleingabe nebeneinander statt
          // in zwei gestapelten Zeilen, damit mehr Platz für die eigentliche
          // Rezeptanzeige bleibt.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SegmentedButton<_Skalierungsmodus>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13)),
                ),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Skalierungsmodus.stueckzahl, label: Text('Stückzahl')),
                  ButtonSegment(value: _Skalierungsmodus.gewicht, label: Text('Gewicht (kg)')),
                ],
                selected: {_modus},
                onSelectionChanged: gewichtVerfuegbar
                    ? (auswahl) => setState(() => _modus = auswahl.first)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _modus == _Skalierungsmodus.stueckzahl
                    ? Row(
                        children: [
                          const Text('Ziel:', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: _stueckzahlController,
                              keyboardType: TextInputType.number,
                              onChanged: _stueckzahlAktualisieren,
                              style: const TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '(Basis: ${r.basisStueckzahl})',
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Text('Ziel:', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: _gewichtController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: _gewichtAktualisieren,
                              style: const TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '(Basis: ${_formatKg(r.basisGewichtKg)} kg)',
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          if (!gewichtVerfuegbar)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Gewichts-Skalierung nicht möglich: Für dieses Rezept sind keine Zutaten in g/kg hinterlegt.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const Divider(height: 28),
          const Text('Zutaten', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...r.zutaten.map((z) {
            final menge = _mengeFuer(z);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118 * _schriftSkalierung,
                    child: Text(
                      _formatiereMengeLinks(menge, z.einheit),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 22 * _schriftSkalierung,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(z.name, style: TextStyle(fontSize: 22 * _schriftSkalierung))),
                ],
              ),
            );
          }),
          const Divider(height: 28),
          const Text('Arbeitsschritte', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...r.schritte.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final schritt = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$index. ', style: TextStyle(fontSize: 22 * _schriftSkalierung, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      schritt.text,
                      style: TextStyle(
                        fontSize: 22 * _schriftSkalierung,
                        fontStyle: schritt.fix ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  if (schritt.fix)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Tooltip(message: 'Wird nicht skaliert (z.B. Temperatur/Zeit)', child: Icon(Icons.lock, size: 20)),
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
