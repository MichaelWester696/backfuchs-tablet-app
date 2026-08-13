import 'package:flutter/material.dart';

import '../models/posten.dart';
import '../services/supabase_service.dart';
import 'home_shell.dart';

/// Kein personenbezogenes Login: Der Mitarbeiter wählt hier nur das Tablet
/// seinem Posten zu (z.B. "Teigmacherei"). Diese Auswahl bleibt für die
/// Laufzeit der App aktiv.
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
