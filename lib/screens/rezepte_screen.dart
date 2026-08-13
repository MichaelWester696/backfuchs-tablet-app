import 'dart:async';

import 'package:flutter/material.dart';

import '../models/posten.dart';
import '../models/rezept.dart';
import '../services/supabase_service.dart';
import 'rezept_detail_screen.dart';

class RezepteScreen extends StatefulWidget {
  final Posten posten;
  const RezepteScreen({super.key, required this.posten});

  @override
  State<RezepteScreen> createState() => _RezepteScreenState();
}

class _RezepteScreenState extends State<RezepteScreen> {
  final _suchController = TextEditingController();
  Timer? _debounce;
  Future<List<Rezept>>? _rezepteFuture;

  @override
  void initState() {
    super.initState();
    _rezepteFuture = SupabaseService.instance.sucheRezepte('');
  }

  void _onSuchtextGeaendert(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _rezepteFuture = SupabaseService.instance.sucheRezepte(text));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _suchController,
            onChanged: _onSuchtextGeaendert,
            decoration: const InputDecoration(
              hintText: 'Rezept suchen...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Rezept>>(
            future: _rezepteFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Fehler: ${snapshot.error}'));
              }
              final rezepte = snapshot.data ?? [];
              if (rezepte.isEmpty) {
                return const Center(child: Text('Keine Rezepte gefunden.'));
              }
              return ListView.builder(
                itemCount: rezepte.length,
                itemBuilder: (context, i) {
                  final r = rezepte[i];
                  return Card(
                    child: ListTile(
                      title: Text(r.name, style: const TextStyle(fontSize: 20)),
                      subtitle: Text('Basis: ${r.basisStueckzahl} Stück · ${r.zutaten.length} Zutaten'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => RezeptDetailScreen(rezept: r)),
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
