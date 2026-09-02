import 'dart:async';

import 'package:flutter/material.dart';

import '../models/backzettel.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

/// Ein anzuzeigender Tabellen-Spalteneintrag - kopf ist die Kopfzeile,
/// quelle der Original-Spaltenname zum Nachschlagen in einer Zeilen-Map.
/// kategorie ('Artikel'/'Menge'/'Teig'/'Dielen'/null) steuert Reihenfolge
/// und Sonderbehandlung (siehe _spaltenPlan/_zelleFuer), istVergleich
/// markiert die zusätzliche "(neu)"-Spalte bei einem Mengenupdate.
class _SpaltenEintrag {
  final String kopf;
  final String quelle;
  final String? kategorie;
  final bool istVergleich;
  const _SpaltenEintrag(this.kopf, this.quelle, {this.kategorie, this.istVergleich = false});
}

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
          maxLines: 1,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

  // Bekannte, lange ERP-Spaltennamen auf kurze Kopfzeilen abbilden, damit die
  // Tabelle nicht unnötig breit wird. Unbekannte Namen werden generisch
  // gekürzt (letztes Wort nach "/", sonst die ersten Zeichen).
  static const _spaltenKurzformen = {
    'bzn / artikel-bezeichnung / einheit': 'Artikel',
    'bestell-menge': 'Menge',
    'teig einwaage': 'Teig',
    'anzahl dielen': 'Dielen',
  };

  String _kuerzeSpaltenname(String name) {
    final kurz = _spaltenKurzformen[name.toLowerCase().trim()];
    if (kurz != null) return kurz;
    final teile = name.split('/');
    final kandidat = teile.first.trim();
    return kandidat.length <= 12 ? kandidat : '${kandidat.substring(0, 11)}…';
  }

  // Zahlen (auch als Text mit Einheit, z.B. "23,497 kg") auf eine
  // Nachkommastelle runden, damit die Tabelle schmaler und ruhiger wirkt.
  String _formatiereWert(dynamic wert) {
    if (wert == null) return '';
    if (wert is num) return _rundeAufEineNachkommastelle(wert.toDouble());
    final text = wert.toString().trim();
    if (text.isEmpty) return '';
    final treffer = RegExp(r'^(-?\d+(?:[.,]\d+)?)\s*(.*)$').firstMatch(text);
    if (treffer == null) return text;
    final zahl = double.tryParse(treffer.group(1)!.replaceAll(',', '.'));
    if (zahl == null) return text;
    final einheit = treffer.group(2)!.trim();
    final formatiert = _rundeAufEineNachkommastelle(zahl);
    return einheit.isEmpty ? formatiert : '$formatiert $einheit';
  }

  String _rundeAufEineNachkommastelle(double wert) {
    final gerundet = (wert * 10).round() / 10;
    final text = gerundet == gerundet.roundToDouble() ? gerundet.toStringAsFixed(0) : gerundet.toStringAsFixed(1);
    return text.replaceAll('.', ',');
  }

  /// Feste Anzeige-Reihenfolge der Spalten, unabhängig von der Reihenfolge
  /// im Import: Artikel zuerst, dann unbekannte/sonstige Spalten, dann Menge
  /// (direkt gefolgt von "Menge (neu)", falls ein Vorgänger-Upload für
  /// dasselbe Datum vorliegt), dann Dielen ebenso, Teig ganz am Ende.
  List<_SpaltenEintrag> _spaltenPlan(Backzettel b) {
    if (b.spalten.isEmpty) return [];
    final hatVergleich = b.vorherigeZeilen != null;
    final artikelSpalte = b.spalten.first;
    String? mengeSpalte, teigSpalte, dielenSpalte;
    final unbekannt = <String>[];
    for (final s in b.spalten.skip(1)) {
      final kategorie = _spaltenKurzformen[s.toLowerCase().trim()];
      if (kategorie == 'Menge') {
        mengeSpalte = s;
      } else if (kategorie == 'Teig') {
        teigSpalte = s;
      } else if (kategorie == 'Dielen') {
        dielenSpalte = s;
      } else {
        unbekannt.add(s);
      }
    }

    final plan = <_SpaltenEintrag>[
      _SpaltenEintrag(_kuerzeSpaltenname(artikelSpalte), artikelSpalte, kategorie: 'Artikel'),
      for (final s in unbekannt) _SpaltenEintrag(_kuerzeSpaltenname(s), s),
    ];
    if (mengeSpalte != null) {
      plan.add(_SpaltenEintrag('Menge', mengeSpalte, kategorie: 'Menge'));
      if (hatVergleich) plan.add(_SpaltenEintrag('Menge (neu)', mengeSpalte, kategorie: 'Menge', istVergleich: true));
    }
    if (dielenSpalte != null) {
      plan.add(_SpaltenEintrag('Dielen', dielenSpalte, kategorie: 'Dielen'));
      if (hatVergleich) plan.add(_SpaltenEintrag('Dielen (neu)', dielenSpalte, kategorie: 'Dielen', istVergleich: true));
    }
    if (teigSpalte != null) plan.add(_SpaltenEintrag('Teig', teigSpalte, kategorie: 'Teig'));
    return plan;
  }

  /// Zeile aus dem vorherigen Upload mit derselben Artikelnummer, oder null
  /// (kein Vorgänger-Upload, oder Artikel darin nicht vorhanden - z.B. neu
  /// hinzugekommen).
  Map<String, dynamic>? _vorherigeZeileFuer(Backzettel b, String artikelNr) {
    final vorherige = b.vorherigeZeilen;
    if (vorherige == null) return null;
    for (final z in vorherige) {
      if ((z['artikel_nr'] as String?) == artikelNr) return z;
    }
    return null;
  }

  /// Baut die Zelle für einen Spalten-Eintrag. Bei Menge/Dielen zeigt die
  /// ursprüngliche Spalte den ALTEN Wert (falls ein Vorgänger-Upload
  /// vorliegt) und die "(neu)"-Spalte den AKTUELLEN Wert - unterscheiden
  /// sich beide, wird die Zelle hervorgehoben.
  DataCell _zelleFuer(_SpaltenEintrag s, Map<String, dynamic> zeile, Map<String, dynamic>? vorherigeZeile, bool hatVergleich) {
    if (s.kategorie == 'Menge' || s.kategorie == 'Dielen') {
      final altWert = _formatiereWert(vorherigeZeile?[s.quelle]);
      final neuWert = _formatiereWert(zeile[s.quelle]);
      final veraendert = hatVergleich && altWert != neuWert;
      final anzeige = s.istVergleich ? neuWert : (hatVergleich ? altWert : neuWert);
      return DataCell(
        Container(
          padding: veraendert ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : EdgeInsets.zero,
          decoration: veraendert
              ? BoxDecoration(color: BackfuchsFarben.gold.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(4))
              : null,
          child: Text(
            anzeige,
            style: TextStyle(fontSize: 13, fontWeight: veraendert ? FontWeight.bold : FontWeight.normal),
          ),
        ),
      );
    }
    if (s.kategorie == 'Artikel') {
      return DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            _formatiereWert(zeile[s.quelle]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    }
    return DataCell(Text(_formatiereWert(zeile[s.quelle]), style: const TextStyle(fontSize: 13)));
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
    final plan = _spaltenPlan(angezeigt);

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 36,
                columnSpacing: 18,
                horizontalMargin: 10,
                columns: [
                  ...plan.map(
                    (s) => DataColumn(
                      label: Text(s.kopf, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const DataColumn(label: Text('Notiz', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                ],
                rows: angezeigt.zeilen.asMap().entries.map((eintrag) {
                  final i = eintrag.key;
                  final zeile = eintrag.value;
                  final artikelNr = zeile['artikel_nr'] as String? ?? '';
                  final notiz = _notizen[artikelNr] ?? '';
                  final vorherigeZeile = _vorherigeZeileFuer(angezeigt, artikelNr);
                  return DataRow(
                    // Jede zweite Zeile bewusst heller als der cremefarbene
                    // Hintergrund (nicht dunkler), wie gewünscht.
                    color: WidgetStatePropertyAll(i.isOdd ? Colors.white : null),
                    cells: [
                      ...plan.map((s) => _zelleFuer(s, zeile, vorherigeZeile, angezeigt.vorherigeZeilen != null)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note, size: 16, color: notiz.isEmpty ? Colors.black38 : BackfuchsFarben.dunkelrot),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 100),
                              child: Text(
                                notiz.isEmpty ? '—' : notiz,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: notiz.isEmpty ? Colors.black38 : Colors.black87),
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
