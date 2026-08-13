import 'package:flutter/material.dart';

import '../models/posten.dart';
import '../services/supabase_service.dart';

class BestandScreen extends StatefulWidget {
  final Posten posten;
  const BestandScreen({super.key, required this.posten});

  @override
  State<BestandScreen> createState() => _BestandScreenState();
}

class _BestandScreenState extends State<BestandScreen> {
  final _produktController = TextEditingController();
  final _mengeController = TextEditingController();
  String _einheit = 'Stück';
  late Future<List<Map<String, dynamic>>> _bestandFuture;

  final _einheiten = const ['Stück', 'kg', 'g', 'l', 'Blech', 'Kiste'];

  @override
  void initState() {
    super.initState();
    _bestandFuture = SupabaseService.instance.ladeBestandHeute(widget.posten.id);
  }

  void _neuLaden() {
    setState(() => _bestandFuture = SupabaseService.instance.ladeBestandHeute(widget.posten.id));
  }

  Future<void> _speichern() async {
    final produkt = _produktController.text.trim();
    final menge = double.tryParse(_mengeController.text.replaceAll(',', '.'));
    if (produkt.isEmpty || menge == null) return;

    await SupabaseService.instance.erfasseBestandszaehlung(
      postenId: widget.posten.id,
      produktName: produkt,
      menge: menge,
      einheit: _einheit,
    );
    _produktController.clear();
    _mengeController.clear();
    _neuLaden();
  }

  @override
  void dispose() {
    _produktController.dispose();
    _mengeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Bestandszählung erfassen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  // Auf schmalen Bildschirmen (z.B. iPhone) passen Produkt, Menge und
                  // Einheit nicht mehr nebeneinander in eine Zeile, ohne dass Beschriftungen
                  // abgeschnitten werden. Deshalb hier je nach verfügbarer Breite entweder
                  // eine Zeile (Tablet) oder zwei gestapelte Zeilen (Handy) anzeigen.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final produktFeld = TextField(
                        controller: _produktController,
                        decoration: const InputDecoration(labelText: 'Produkt'),
                      );
                      final mengeFeld = TextField(
                        controller: _mengeController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Menge'),
                      );
                      final einheitFeld = DropdownButtonFormField<String>(
                        value: _einheit,
                        items: _einheiten.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setState(() => _einheit = v ?? _einheit),
                        decoration: const InputDecoration(labelText: 'Einheit'),
                      );

                      if (constraints.maxWidth >= 500) {
                        return Row(
                          children: [
                            Expanded(flex: 3, child: produktFeld),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: mengeFeld),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: einheitFeld),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          produktFeld,
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: mengeFeld),
                              const SizedBox(width: 12),
                              Expanded(child: einheitFeld),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(onPressed: _speichern, child: const Text('Hinzufügen')),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _bestandFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final eintraege = snapshot.data ?? [];
              if (eintraege.isEmpty) {
                return const Center(child: Text('Heute noch keine Zählung erfasst.'));
              }
              return ListView.builder(
                itemCount: eintraege.length,
                itemBuilder: (context, i) {
                  final e = eintraege[i];
                  return ListTile(
                    title: Text(e['produkt_name'] as String),
                    trailing: Text('${e['menge']} ${e['einheit']}', style: const TextStyle(fontSize: 18)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
