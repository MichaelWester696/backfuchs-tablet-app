import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/posten.dart';
import '../services/supabase_service.dart';
import 'home_shell.dart';

/// URL des Führungskräfte-Dashboards (Web, responsiv - auch auf Tablet nutzbar).
const _dashboardUrl = 'https://project-2bxf4.vercel.app/dashboard.html';

/// Kein personenbezogenes Login: Der Mitarbeiter wählt hier nur das Tablet
/// seinem Posten zu (z.B. "Teigmacherei"). Diese Auswahl bleibt für die
/// Laufzeit der App aktiv. Zusätzlich gibt es einen PIN-geschützten Zugang
/// zum Führungskräfte-Dashboard für die Backstubenleitung.
class PostenLoginScreen extends StatefulWidget {
  const PostenLoginScreen({super.key});

  @override
  State<PostenLoginScreen> createState() => _PostenLoginScreenState();
}

class _PostenLoginScreenState extends State<PostenLoginScreen> {
  late Future<List<Posten>> _postenFuture;

  @override
  void initState() {
    super.initState();
    _postenFuture = SupabaseService.instance.ladePosten();
  }

  Future<void> _backstubenleitungOeffnen() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PinDialog(),
    );
    if (pin == null || !mounted) return;

    final korrekt = await SupabaseService.instance.pruefeLeitungsPin(pin);
    if (!mounted) return;

    if (!korrekt) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falscher PIN.')),
      );
      return;
    }

    final url = Uri.parse(_dashboardUrl);
    final geoeffnet = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!geoeffnet && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dashboard konnte nicht geöffnet werden.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Wester's Backfuchs")),
      body: FutureBuilder<List<Posten>>(
        future: _postenFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Fehler beim Laden der Posten:\n${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final posten = snapshot.data ?? [];
          if (posten.isEmpty) {
            return const Center(child: Text('Keine Posten gefunden. Bitte in Supabase anlegen.'));
          }
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('Für welchen Posten ist dieses Tablet?', style: TextStyle(fontSize: 22)),
                ),
                Expanded(
                  // Passt die Spaltenzahl automatisch an die Bildschirmbreite an:
                  // schmales iPhone bekommt 1-2 Spalten, ein Tablet 3-5, statt
                  // fest auf 3 Spalten zu bestehen und die Kacheln zu quetschen.
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: posten.length,
                    itemBuilder: (context, i) => _PostenKachel(posten: posten[i]),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _backstubenleitungOeffnen,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Backstubenleitung'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PostenKachel extends StatelessWidget {
  final Posten posten;
  const _PostenKachel({required this.posten});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeShell(posten: posten)),
          );
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              posten.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

/// Einfacher PIN-Eingabedialog. Gibt den eingegebenen PIN als String zurück
/// (Prüfung erfolgt im Aufrufer gegen Supabase), oder null bei Abbruch.
class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN für Backstubenleitung'),
      content: TextField(
        controller: _pinController,
        keyboardType: TextInputType.number,
        obscureText: true,
        autofocus: true,
        maxLength: 8,
        decoration: const InputDecoration(labelText: 'PIN'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_pinController.text),
          child: const Text('Bestätigen'),
        ),
      ],
    );
  }
}
