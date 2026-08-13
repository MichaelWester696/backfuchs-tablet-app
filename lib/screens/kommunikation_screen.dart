import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/nachricht.dart';
import '../models/posten.dart';
import '../services/supabase_service.dart';

class KommunikationScreen extends StatefulWidget {
  final Posten posten;
  const KommunikationScreen({super.key, required this.posten});

  @override
  State<KommunikationScreen> createState() => _KommunikationScreenState();
}

class _KommunikationScreenState extends State<KommunikationScreen> {
  final _textController = TextEditingController();
  late Stream<List<Nachricht>> _stream;
  late Future<List<Posten>> _allePostenFuture;
  String _zielTyp = 'leitung';
  Posten? _zielPosten;

  @override
  void initState() {
    super.initState();
    _stream = SupabaseService.instance.nachrichtenStream();
    _allePostenFuture = SupabaseService.instance.ladePosten();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool _relevant(Nachricht n) {
    return n.vonPostenId == widget.posten.id ||
        n.anPostenId == widget.posten.id ||
        (n.zielTyp == 'leitung' && n.vonPostenId == null); // Nachrichten der Leitung an alle
  }

  Future<void> _senden() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await SupabaseService.instance.sendeNachricht(
      vonPostenId: widget.posten.id,
      zielTyp: _zielTyp,
      anPostenId: _zielTyp == 'posten' ? _zielPosten?.id : null,
      text: text,
    );
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Nachricht>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final nachrichten = snapshot.data!.where(_relevant).toList()
                ..sort((a, b) => a.erstelltAm.compareTo(b.erstelltAm));
              if (nachrichten.isEmpty) {
                return const Center(child: Text('Noch keine Nachrichten.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: nachrichten.length,
                itemBuilder: (context, i) {
                  final n = nachrichten[i];
                  final vonMir = n.vonPostenId == widget.posten.id;
                  return Align(
                    alignment: vonMir ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
                      decoration: BoxDecoration(
                        color: vonMir ? Colors.amber.shade100 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.text, style: const TextStyle(fontSize: 17)),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd.MM. HH:mm').format(n.erstelltAm.toLocal()),
                            style: const TextStyle(fontSize: 12, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                FutureBuilder<List<Posten>>(
                  future: _allePostenFuture,
                  builder: (context, snapshot) {
                    final andere = (snapshot.data ?? []).where((p) => p.id != widget.posten.id).toList();
                    return Row(
                      children: [
                        const Text('An:'),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Leitung'),
                          selected: _zielTyp == 'leitung',
                          onSelected: (_) => setState(() => _zielTyp = 'leitung'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<Posten>(
                            hint: const Text('...oder anderer Posten'),
                            isExpanded: true,
                            value: _zielTyp == 'posten' ? _zielPosten : null,
                            items: andere
                                .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                                .toList(),
                            onChanged: (p) => setState(() {
                              _zielTyp = 'posten';
                              _zielPosten = p;
                            }),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: const InputDecoration(hintText: 'Nachricht...'),
                        onSubmitted: (_) => _senden(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _senden, icon: const Icon(Icons.send)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
