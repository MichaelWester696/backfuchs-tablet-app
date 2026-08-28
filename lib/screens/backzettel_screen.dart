import 'dart:async';

import 'package:flutter/material.dart';

import '../models/backzettel.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class BackzettelScreen extends StatefulWidget {
  const BackzettelScreen({super.key});

  @override
  State<BackzettelScreen> createState() => _BackzettelScreenState();
}

class _BackzettelScreenState extends State<BackzettelScreen> {
  List<Backzettel> _verlauf = [];
  Backzettel? _angezeigt;
  Map<String, String> _notizen = {};
  bool _laedt = true;
  bool _fehler = false;
  StreamSubscription<Map<String, String>>? _notizenAbo;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _notizenAbo?.cancel();
    super.dispose();
  }

  String get _heuteIso {
    final jetzt = DateTime.now();
    return '${jetzt.year.toString().padLeft(4, '0')}-${jetzt.month.toString().padLeft(2, '0')}-${jetzt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _laden() async {
    setState(() {
      _laedt = true;
      _fehler = false;
    });
    try {
      final verlauf = await SupabaseService.instance.ladeBackzettelVerlauf();
      Backzettel? aktuell;
      for (final b in verlauf) {
        if (b.arbeitsdatum == _heuteIso) {
          aktuell = b;
          break;
        }
      }
      aktuell ??= verlauf.isNotEmpty ? verlauf.first : null;
      if (!mounted) return;
      setState(() {
        _verlauf = verlauf;
        _angezeigt = aktuell;
        _laedt = false;
      });
      if (aktuell != null) await _zettelAnzeigen(aktuell);
    } catch (_) {
      if (mounted) {
        setState(() {
          _laedt = false;
          _fehler = true;
        });
      }
    }
  }

  Future<void> _zettelAnzeigen(Backzettel b) async {
    setState(() => _angezeigt = b);
    final notizen = await SupabaseService.instance.ladeBackzettelNotizen(b.arbeitsdatum);
    if (!mounted || _angezeigt?.arbeitsdatum != b.arbeitsdatum) return;
    setState(() => _notizen = notizen);

    _notizenAbo?.cancel();
    _notizenAbo = SupabaseService.instance.backzettelNotizenStream(b.arbeitsdatum).listen((notizen) {
      if (mounted) setState(() => _notizen = notizen);
    });
  }

  Future<void> _notizBearbeiten(Map<String, dynamic> zeile) async {
    final angezeigt = _angezeigt;
    if (angezeigt == null) return;
    final artikelNr = zeile['artikel_nr'] as String? ?? '';
    if (artikelNr.isEmpty) return;

    final controller = TextEditingController(text: _notizen[artikelNr] ?? '');
    final ergebnis = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Notiz: $artikelNr'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'z.B. Bestandsmenge'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (ergebnis == null) return;

    setState(() => _notizen = {..._notizen, artikelNr: ergebnis});
    try {
      await SupabaseService.instance.speichereBackzettelNotiz(
        arbeitsdatum: angezeigt.arbeitsdatum,
        artikelNr: artikelNr,
        notiz: ergebnis,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notiz konnte nicht gespeichert werden.')),
        );
      }
    }
  }

  static const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  String _datumKurz(String iso) {
    try {
      final d = DateTime.parse(iso);
      final tag = _wochentage[d.weekday - 1];
      return '$tag ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_laedt) return const Center(child: CircularProgressIndicator());
    if (_fehler) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Backzettel konnte nicht geladen werden.', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _laden, icon: const Icon(Icons.refresh), label: const Text('Erneut versuchen')),
          ],
        ),
      );
    }
    if (_verlauf.isEmpty || _angezeigt == null) {
      return const Center(child: Text('Noch kein Backzettel hochgeladen.', style: TextStyle(fontSize: 18)));
    }

    final angezeigt = _angezeigt!;
    final istHeute = angezeigt.arbeitsdatum == _heuteIso;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  istHeute ? 'Backzettel heute' : 'Backzettel ${_datumKurz(angezeigt.arbeitsdatum)}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(onPressed: _laden, icon: const Icon(Icons.refresh), tooltip: 'Aktualisieren'),
            ],
          ),
        ),
        if (!istHeute)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(color: BackfuchsFarben.gold.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
              child: const Text('Für heute liegt noch kein Backzettel vor - zeigt den letzten verfügbaren Stand.'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _verlauf.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final b = _verlauf[i];
                final ausgewaehlt = b.arbeitsdatum == angezeigt.arbeitsdatum;
                return ChoiceChip(
                  label: Text(_datumKurz(b.arbeitsdatum)),
                  selected: ausgewaehlt,
                  onSelected: (_) => _zettelAnzeigen(b),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  ...angezeigt.spalten.map(
                    (s) => DataColumn(label: Text(s, style: const TextStyle(fontWeight: FontWeight.bold))),
                  ),
                  const DataColumn(label: Text('Notiz', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: angezeigt.zeilen.map((zeile) {
                  final artikelNr = zeile['artikel_nr'] as String? ?? '';
                  final notiz = _notizen[artikelNr] ?? '';
                  return DataRow(
                    cells: [
                      ...angezeigt.spalten.map((s) => DataCell(Text(zeile[s]?.toString() ?? ''))),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note, size: 18, color: notiz.isEmpty ? Colors.black38 : BackfuchsFarben.dunkelrot),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                notiz.isEmpty ? '—' : notiz,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: notiz.isEmpty ? Colors.black38 : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _notizBearbeiten(zeile),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
