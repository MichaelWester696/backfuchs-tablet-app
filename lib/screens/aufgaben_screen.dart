import 'package:flutter/material.dart';

import '../models/aufgabe.dart';
import '../models/posten.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'posten_login_screen.dart';

class AufgabenScreen extends StatefulWidget {
  final Posten posten;
  const AufgabenScreen({super.key, required this.posten});

  @override
  State<AufgabenScreen> createState() => _AufgabenScreenState();
}

class _AufgabenScreenState extends State<AufgabenScreen> {
  late Stream<List<Aufgabe>> _stream;
  bool _pruefeSchichtLaeuft = true;
  bool _schichtAbgeschlossen = false;

  @override
  void initState() {
    super.initState();
    _stream = SupabaseService.instance.aufgabenStream(widget.posten.id);
    _ladeSchichtStatus();
  }

  Future<void> _ladeSchichtStatus() async {
    final abgeschlossen = await SupabaseService.instance.pruefeSchichtAbgeschlossen(widget.posten.id);
    if (mounted) {
      setState(() {
        _schichtAbgeschlossen = abgeschlossen;
        _pruefeSchichtLaeuft = false;
      });
    }
  }

  Future<void> _schichtAbschliessen() async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Schicht abschließen?'),
        content: const Text(
          'Damit wird die Backstubenleitung informiert. Noch nicht erledigte Aufgaben von heute '
          'werden im Führungsdashboard hervorgehoben, damit kurzfristig nachgefasst werden kann.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Schicht abschließen')),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;
    await SupabaseService.instance.schliesseSchichtAb(widget.posten.id);
    if (!mounted) return;
    // Zurück zur Posten-Auswahl, damit das Tablet für den nächsten Posten
    // bzw. die nächste Schicht bereit ist.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PostenLoginScreen()),
    );
  }

  bool _istHeute(Aufgabe a) {
    final heute = DateTime.now();
    return a.faelligkeitsdatum.year == heute.year &&
        a.faelligkeitsdatum.month == heute.month &&
        a.faelligkeitsdatum.day == heute.day;
  }

  Future<void> _bestaetigen(Aufgabe a) async {
    await SupabaseService.instance.aufgabeBestaetigen(a.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Aufgabe>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final aufgaben = snapshot.data!.where(_istHeute).toList()
                ..sort((a, b) {
                  // Einmalige Aufgaben immer oben, danach die vom Dashboard aus
                  // einstellbare Reihenfolge (Wecker-Wochentage erzeugen die
                  // wiederkehrenden Aufgaben, quelle=system).
                  if (a.wiederkehrend != b.wiederkehrend) {
                    return a.wiederkehrend ? 1 : -1;
                  }
                  final r = a.reihenfolge.compareTo(b.reihenfolge);
                  if (r != 0) return r;
                  return (a.uhrzeit ?? '99:99').compareTo(b.uhrzeit ?? '99:99');
                });

              if (aufgaben.isEmpty) {
                return const Center(child: Text('Keine Aufgaben für heute. 🎉', style: TextStyle(fontSize: 20)));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: aufgaben.length,
                itemBuilder: (context, i) => _AufgabenKarte(aufgabe: aufgaben[i], onBestaetigen: _bestaetigen),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: _pruefeSchichtLaeuft
                  ? const SizedBox.shrink()
                  : _schichtAbgeschlossen
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.check_circle, color: BackfuchsFarben.gruen),
                          label: const Text('Schicht heute abgeschlossen'),
                        )
                      : OutlinedButton.icon(
                          onPressed: _schichtAbschliessen,
                          icon: const Icon(Icons.logout),
                          label: const Text('Schicht abschließen'),
                        ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AufgabenKarte extends StatelessWidget {
  final Aufgabe aufgabe;
  final Future<void> Function(Aufgabe) onBestaetigen;

  const _AufgabenKarte({required this.aufgabe, required this.onBestaetigen});

  Color get _dringlichkeitsFarbe {
    switch (aufgabe.dringlichkeit) {
      case 'hoch':
        return BackfuchsFarben.rot;
      case 'niedrig':
        return Colors.black38;
      default:
        return BackfuchsFarben.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 10,
          decoration: BoxDecoration(color: _dringlichkeitsFarbe, borderRadius: BorderRadius.circular(6)),
        ),
        title: Text(
          aufgabe.titel,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            decoration: aufgabe.erledigt ? TextDecoration.lineThrough : null,
            color: aufgabe.erledigt ? Colors.black45 : Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (aufgabe.beschreibung != null && aufgabe.beschreibung!.isNotEmpty)
              Text(aufgabe.beschreibung!),
            Row(
              children: [
                if (aufgabe.uhrzeit != null) ...[
                  const Icon(Icons.access_time, size: 16),
                  const SizedBox(width: 4),
                  Text(aufgabe.uhrzeitKurz),
                  const SizedBox(width: 12),
                ],
                if (aufgabe.quelle == 'whatsapp') const Icon(Icons.chat, size: 16, color: Colors.green),
                if (aufgabe.wiederkehrend) const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.repeat, size: 16),
                ),
              ],
            ),
          ],
        ),
        trailing: aufgabe.erledigt
            ? const Icon(Icons.check_circle, color: BackfuchsFarben.gruen, size: 32)
            : ElevatedButton(
                onPressed: () => onBestaetigen(aufgabe),
                child: const Text('Erledigt'),
              ),
      ),
    );
  }
}
