import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/defekt.dart';
import '../models/posten.dart';
import '../services/supabase_service.dart';

class DefektScreen extends StatefulWidget {
  final Posten posten;
  const DefektScreen({super.key, required this.posten});

  @override
  State<DefektScreen> createState() => _DefektScreenState();
}

class _DefektScreenState extends State<DefektScreen> {
  final _maschineController = TextEditingController();
  final _beschreibungController = TextEditingController();
  XFile? _foto;
  // Bytes werden direkt beim Aufnehmen einmal eingelesen und im State gehalten.
  // Wichtig für Web (PWA): dart:io File funktioniert im Browser nicht, weder
  // zum erneuten Einlesen noch für die Vorschau (Image.file) - deshalb hier
  // ausschließlich mit Bytes + Image.memory arbeiten, das läuft auf allen
  // Plattformen (Android, iOS, Web) gleich.
  Uint8List? _fotoBytes;
  bool _wirdGesendet = false;
  String? _fehlermeldung;
  late Future<List<Defekt>> _defekteFuture;

  @override
  void initState() {
    super.initState();
    _defekteFuture = SupabaseService.instance.ladeDefekte(widget.posten.id);
  }

  @override
  void dispose() {
    _maschineController.dispose();
    _beschreibungController.dispose();
    super.dispose();
  }

  Future<void> _fotoAufnehmen() async {
    final foto = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
    if (foto == null) return;
    final bytes = await foto.readAsBytes();
    setState(() {
      _foto = foto;
      _fotoBytes = bytes;
    });
  }

  void _neuLaden() {
    setState(() => _defekteFuture = SupabaseService.instance.ladeDefekte(widget.posten.id));
  }

  Future<void> _senden() async {
    final maschine = _maschineController.text.trim();
    final beschreibung = _beschreibungController.text.trim();
    if (maschine.isEmpty || beschreibung.isEmpty) return;

    setState(() {
      _wirdGesendet = true;
      _fehlermeldung = null;
    });
    try {
      String? fotoUrl;
      if (_foto != null && _fotoBytes != null) {
        fotoUrl = await SupabaseService.instance.ladeDefektFotoUrl(_foto!.name, _fotoBytes!);
      }
      await SupabaseService.instance.meldeDefekt(
        postenId: widget.posten.id,
        maschine: maschine,
        beschreibung: beschreibung,
        fotoUrl: fotoUrl,
      );
      _maschineController.clear();
      _beschreibungController.clear();
      setState(() {
        _foto = null;
        _fotoBytes = null;
      });
      _neuLaden();
    } catch (e) {
      // Fehler nicht mehr lautlos verschlucken, sondern sichtbar machen.
      setState(() => _fehlermeldung = 'Senden fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _wirdGesendet = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Defekt melden', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _maschineController,
                  decoration: const InputDecoration(labelText: 'Maschine / Anlage'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _beschreibungController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Was ist defekt?'),
                ),
                const SizedBox(height: 12),
                if (_fotoBytes != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_fotoBytes!, height: 160, fit: BoxFit.cover),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _fotoAufnehmen,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_fotoBytes == null ? 'Foto aufnehmen' : 'Foto ändern'),
                ),
                if (_fehlermeldung != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_fehlermeldung!, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _wirdGesendet ? null : _senden,
                  child: _wirdGesendet
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Defekt melden'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Bisherige Meldungen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        FutureBuilder<List<Defekt>>(
          future: _defekteFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
            }
            final defekte = snapshot.data ?? [];
            if (defekte.isEmpty) {
              return const Padding(padding: EdgeInsets.all(16), child: Text('Keine Meldungen vorhanden.'));
            }
            return Column(
              children: defekte
                  .map((d) => Card(
                        child: ListTile(
                          leading: d.fotoUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(d.fotoUrl!, width: 56, height: 56, fit: BoxFit.cover),
                                )
                              : const Icon(Icons.build, size: 32),
                          title: Text(d.maschine),
                          subtitle: Text(d.beschreibung),
                          trailing: Chip(
                            label: Text(d.status, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            backgroundColor: _statusFarbe(d.status),
                          ),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}
