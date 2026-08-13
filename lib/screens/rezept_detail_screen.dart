import 'package:flutter/material.dart';

import '../models/rezept.dart';

class RezeptDetailScreen extends StatefulWidget {
  final Rezept rezept;
  const RezeptDetailScreen({super.key, required this.rezept});

  @override
  State<RezeptDetailScreen> createState() => _RezeptDetailScreenState();
}

class _RezeptDetailScreenState extends State<RezeptDetailScreen> {
  late int _zielStueckzahl;
  late TextEditingController _stueckzahlController;

  @override
  void initState() {
    super.initState();
    _zielStueckzahl = widget.rezept.basisStueckzahl;
    _stueckzahlController = TextEditingController(text: _zielStueckzahl.toString());
  }

  @override
  void dispose() {
    _stueckzahlController.dispose();
    super.dispose();
  }

  void _aktualisieren(String value) {
    final n = int.tryParse(value);
    if (n != null && n > 0) {
      setState(() => _zielStueckzahl = n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rezept;
    return Scaffold(
      appBar: AppBar(title: Text(r.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Text('Zielstückzahl:', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 16),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _stueckzahlController,
                  keyboardType: TextInputType.number,
                  onChanged: _aktualisieren,
                  style: const TextStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              Text('(Basis: ${r.basisStueckzahl})', style: const TextStyle(color: Colors.black54)),
            ],
          ),
          const Divider(height: 32),
          const Text('Zutaten', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...r.zutaten.map((z) {
            final menge = r.umgerechneteMenge(z, _zielStueckzahl);
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
