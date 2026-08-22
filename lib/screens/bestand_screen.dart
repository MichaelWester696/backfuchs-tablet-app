import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bestand_produkt.dart';
import '../models/posten.dart';
import '../services/supabase_service.dart';

class BestandScreen extends StatefulWidget {
  final Posten posten;
  const BestandScreen({super.key, required this.posten});

  @override
  State<BestandScreen> createState() => _BestandScreenState();
}

class _BestandScreenState extends State<BestandScreen> {
  final _mengeController = TextEditingController();
  BestandProdukt? _ausgewaehltesProdukt;
  bool _wirdGespeichert = false;
  String? _fehlermeldung;

  late Future<List<BestandProdukt>> _produkteFuture;
  late Future<List<BestandEintrag>> _bestandFuture;

  @override
  void initState() {
    super.initState();
    _produkteFuture = SupabaseService.instance.ladeBestandProdukte();
    _bestandFuture = SupabaseService.instance.ladeBestandAktuell(widget.posten.id);
  }

  void _neuLaden() {
    setState(() => _bestandFuture = SupabaseService.instance.ladeBestandAktuell(widget.posten.id));
  }

  Future<void> _speichern() async {
    final produkt = _ausgewaehltesProdukt;
    final menge = double.tryParse(_mengeController.text.replaceAll(',', '.'));
    if (produkt == null || menge == null) {
      setState(() => _fehlermeldung = 'Bitte Produkt auswählen und eine gültige Menge eingeben.');
      return;
    }

    setState(() {
      _wirdGespeichert = true;
      _fehlermeldung = null;
    });
    try {
      await SupabaseService.instance.erfasseBestandszaehlung(
        postenId: widget.posten.id,
        produkt: produkt,
        menge: menge,
      );
      _mengeController.clear();
      setState(() => _ausgewaehltesProdukt = null);
      _neuLaden();
    } catch (e) {
      setState(() => _fehlermeldung = 'Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _wirdGespeichert = false);
    }
  }

  @override
  void dispose() {
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
                  const SizedBox(height: 4),
                  const Text(
                    'Ein erneutes Speichern überschreibt den bisherigen Wert für dieses Produkt.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<BestandProdukt>>(
                    future: _produkteFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        );
                      }
                      final produkte = snapshot.data!;
                      if (produkte.isEmpty) {
                        return const Text(
                          'Noch keine Produkte hinterlegt. Bitte im Führungsdashboard unter\n"Bestandsprodukte verwalten" anlegen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        );
                      }
                      // Referenz aktualisieren, falls z.B. der Name sich seit
                      // dem letzten Laden geändert hat (oder das Produkt
                      // zwischenzeitlich deaktiviert wurde).
                      if (_ausgewaehltesProdukt != null) {
                        BestandProdukt? gefunden;
                        for (final p in produkte) {
                          if (p.id == _ausgewaehltesProdukt!.id) {
                            gefunden = p;
                            break;
                          }
                        }
                        _ausgewaehltesProdukt = gefunden;
                      }
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final produktFeld = DropdownButtonFormField<BestandProdukt>(
                            value: _ausgewaehltesProdukt,
                            isExpanded: true,
                            items: produkte
                                .map((p) => DropdownMenuItem(value: p, child: Text('${p.name} (${p.einheit})')))
                                .toList(),
                            onChanged: (p) => setState(() => _ausgewaehltesProdukt = p),
                            decoration: const InputDecoration(labelText: 'Produkt'),
                          );
                          final mengeFeld = TextField(
                            controller: _mengeController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Menge',
                              suffixText: _ausgewaehltesProdukt?.einheit,
                            ),
                          );

                          if (constraints.maxWidth >= 500) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: produktFeld),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: mengeFeld),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              produktFeld,
                              const SizedBox(height: 12),
                              mengeFeld,
                            ],
                          );
                        },
                      );
                    },
                  ),
                  if (_fehlermeldung != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_fehlermeldung!, style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _wirdGespeichert ? null : _speichern,
                      child: _wirdGespeichert
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Speichern'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: FutureBuilder<List<BestandEintrag>>(
            future: _bestandFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final eintraege = snapshot.data ?? [];
              if (eintraege.isEmpty) {
                return const Center(child: Text('Noch keine Zählung erfasst.'));
              }
              return ListView.builder(
                itemCount: eintraege.length,
                itemBuilder: (context, i) {
                  final e = eintraege[i];
                  return ListTile(
                    title: Text(e.produktName),
                    subtitle: Text(
                      'Stand: ${DateFormat('dd.MM. HH:mm').format(e.aktualisiertAm.toLocal())} Uhr',
                      style: const TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                    trailing: Text('${e.menge} ${e.einheit}', style: const TextStyle(fontSize: 18)),
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
