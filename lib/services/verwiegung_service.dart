import 'package:supabase_flutter/supabase_flutter.dart';

import '../verwiegung/rohstoffstamm.dart';
import 'offline/local_cache.dart';

/// Supabase-Zugriffe der Verwiegung (Rohstoffstamm lesen, Protokolle schreiben).
class VerwiegungService {
  VerwiegungService._();
  static final VerwiegungService instance = VerwiegungService._();

  SupabaseClient get _client => Supabase.instance.client;

  List<Map<String, dynamic>> _zeilen(dynamic rows) =>
      (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();

  /// Lädt den Rohstoffstamm und merkt ihn sich lokal. Ohne Verbindung wird
  /// der zuletzt gemerkte Stand benutzt; gab es noch nie einen, ist der Stamm leer
  /// (dann zeigt die Verwiegung für alle Zutaten einen Hinweis).
  Future<Rohstoffstamm> ladeStamm() async {
    try {
      final rohstoffe = _zeilen(await _client.from('rohstoffe').select().eq('aktiv', true));
      final aliase = _zeilen(await _client.from('rohstoff_aliase').select());
      final positionen = _zeilen(await _client.from('verwiegepositionen').select().order('nr'));
      await LocalCache.instance.rohstoffstammSpeichern(
        rohstoffe: rohstoffe,
        aliase: aliase,
        positionen: positionen,
      );
      return Rohstoffstamm.ausJson(rohstoffe: rohstoffe, aliase: aliase, positionen: positionen);
    } catch (_) {
      final zwischengespeichert = LocalCache.instance.rohstoffstammLaden();
      if (zwischengespeichert == null) return Rohstoffstamm.leer();
      return Rohstoffstamm.ausJson(
        rohstoffe: zwischengespeichert['rohstoffe']!,
        aliase: zwischengespeichert['aliase']!,
        positionen: zwischengespeichert['positionen']!,
      );
    }
  }

  /// Speichert das Protokoll einer Verwiegung. Schlägt die Übertragung fehl,
  /// wird sie für die nächste Verbindung in die Outbox gelegt (die Zeile hat
  /// eine vom Gerät vergebene ID, ein erneutes Senden legt also keine Dublette an).
  Future<void> speichereProtokoll(Map<String, dynamic> zeile) async {
    try {
      await _client.from('verwiegungen').upsert(zeile, onConflict: 'id');
    } catch (_) {
      await LocalCache.instance.outboxHinzufuegen({
        'type': 'verwiegung_protokoll',
        'zeile': zeile,
      });
    }
  }
}
