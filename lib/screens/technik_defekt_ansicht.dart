import 'package:flutter/material.dart';

import '../models/defekt.dart';
import '../services/supabase_service.dart';

/// Defekt-Verwaltung für den festen Posten "Technik": zeigt alle Defekte
/// über alle Posten hinweg chronologisch, mit Offen/Erledigt-Umschalter und
/// der Möglichkeit, Defekte als erledigt zu markieren.
class TechnikDefektAnsicht extends StatefulWidget {
  const TechnikDefektAnsicht({super.key});

  @override
  State<TechnikDefektAnsicht> createState() => _TechnikDefektAnsichtState();
}

class _TechnikDefektAnsichtState extends State<TechnikDefektAnsicht> {
  bool _zeigeErledigt = false;
  late Future<List<Defekt>> _defekteFuture;

  @override
  void initState() {
    super.initState();
    _defekteFuture = SupabaseService.instance.ladeAlleDefekte();
  }

  void _neuLaden() {
    setState(() => _defekteFuture = SupabaseService.instance.ladeAlleDefekte());
  }

  Future<void> _markiereErledigt(Defekt d) async {
    await SupabaseService.instance.markiereDefektErledigt(d.id);
    _neuLaden();
  }

  Color _statusFarbe(String status) {
    switch (status) {
      case 'behoben':
        return Colors.green;
      case 'in_bearbeitung':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  void _detailPopupZeigen(Defekt d) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${d.maschine} — ${d.postenName ?? "?"}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                if (d.fotoUrl != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(d.fotoUrl!, fit: BoxFit.contain),
                    ),
                  ),
                Text(d.beschreibung, style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Offen')),
              ButtonSegment(value: true, label: Text('Erledigt')),
            ],
            selected: {_zeigeErledigt},
            onSelectionChanged: (sel) => setState(() => _zeigeErledigt = sel.first),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Defekt>>(
            future: _defekteFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final alle = snapshot.data ?? [];
              final gefiltert = alle.where((d) => _zeigeErledigt ? d.status == 'behoben' : d.status != 'behoben').toList()
                ..sort((a, b) => _zeigeErledigt
                    ? (b.behobenAm ?? b.gemeldetAm).compareTo(a.behobenAm ?? a.gemeldetAm)
                    : a.gemeldetAm.compareTo(b.gemeldetAm));

              if (gefiltert.isEmpty) {
                return Center(
                  child: Text(
                    _zeigeErledigt ? 'Noch keine erledigten Defekte.' : 'Keine offenen Defekte. 🎉',
                    style: const TextStyle(fontSize: 18),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: gefiltert.length,
                itemBuilder: (context, i) {
                  final d = gefiltert[i];
                  return Card(
                    child: ListTile(
                      onTap: () => _detailPopupZeigen(d),
                      leading: d.fotoUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(d.fotoUrl!, width: 56, height: 56, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.build, size: 32),
                      title: Text('${d.maschine} — ${d.postenName ?? "?"}'),
                      subtitle: Text(d.beschreibung),
                      trailing: _zeigeErledigt
                          ? Chip(
                              label: const Text('erledigt', style: TextStyle(color: Colors.white, fontSize: 12)),
                              backgroundColor: _statusFarbe(d.status),
                            )
                          : ElevatedButton(
                              onPressed: () => _markiereErledigt(d),
                              child: const Text('Erledigt'),
                            ),
                    ),
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
