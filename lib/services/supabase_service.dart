import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/aufgabe.dart';
import '../models/defekt.dart';
import '../models/nachricht.dart';
import '../models/posten.dart';
import '../models/rezept.dart';

/// Bündelt alle Supabase-Zugriffe der App an einer Stelle.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ---------------------------------------------------------------------
  // Posten
  // ---------------------------------------------------------------------
  Future<List<Posten>> ladePosten() async {
    final rows = await _client.from('posten').select().eq('aktiv', true).order('reihenfolge');
    return (rows as List).map((r) => Posten.fromJson(r as Map<String, dynamic>)).toList();
  }

  // ---------------------------------------------------------------------
  // Aufgaben
  // ---------------------------------------------------------------------
  Future<List<Aufgabe>> ladeAufgabenFuerHeute(String postenId) async {
    final heute = DateTime.now().toIso8601String().split('T').first;
    final rows = await _client
        .from('aufgaben')
        .select()
        .eq('posten_id', postenId)
        .eq('faelligkeitsdatum', heute)
        .order('dringlichkeit', ascending: false)
        .order('uhrzeit', ascending: true);
    return (rows as List).map((r) => Aufgabe.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Realtime-Stream aller Aufgaben eines Postens (App filtert clientseitig auf "heute").
  Stream<List<Aufgabe>> aufgabenStream(String postenId) {
    return _client
        .from('aufgaben')
        .stream(primaryKey: ['id'])
        .eq('posten_id', postenId)
        .map((rows) => rows.map((r) => Aufgabe.fromJson(r)).toList());
  }

  Future<void> aufgabeBestaetigen(String aufgabeId) async {
    await _client.from('aufgaben').update({
      'status': 'erledigt',
      'erledigt_am': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', aufgabeId);
  }

  // ---------------------------------------------------------------------
  // Rezepte
  // ---------------------------------------------------------------------
  Future<List<Rezept>> sucheRezepte(String suchbegriff) async {
    var query = _client.from('rezepte').select();
    if (suchbegriff.trim().isNotEmpty) {
      query = query.ilike('name', '%${suchbegriff.trim()}%');
    }
    final rows = await query.order('name');
    return (rows as List).map((r) => Rezept.fromJson(r as Map<String, dynamic>)).toList();
  }

  // ---------------------------------------------------------------------
  // Kommunikation
  // ---------------------------------------------------------------------
  /// Nachrichten, die für diesen Posten relevant sind: entweder direkt an ihn
  /// gerichtet, von ihm gesendet, oder generelle Nachrichten an die Leitung.
  Future<List<Nachricht>> ladeNachrichten(String postenId) async {
    final rows = await _client
        .from('nachrichten')
        .select()
        .or('von_posten_id.eq.$postenId,an_posten_id.eq.$postenId')
        .order('erstellt_am', ascending: false)
        .limit(200);
    return (rows as List).map((r) => Nachricht.fromJson(r as Map<String, dynamic>)).toList();
  }

  Stream<List<Nachricht>> nachrichtenStream() {
    return _client
        .from('nachrichten')
        .stream(primaryKey: ['id'])
        .order('erstellt_am')
        .map((rows) => rows.map((r) => Nachricht.fromJson(r)).toList());
  }

  Future<void> sendeNachricht({
    required String? vonPostenId,
    required String zielTyp, // 'posten' | 'leitung'
    String? anPostenId,
    required String text,
  }) async {
    await _client.from('nachrichten').insert({
      'von_posten_id': vonPostenId,
      'ziel_typ': zielTyp,
      'an_posten_id': anPostenId,
      'text': text,
    });
  }

  // ---------------------------------------------------------------------
  // Bestandszählung
  // ---------------------------------------------------------------------
  Future<void> erfasseBestandszaehlung({
    required String postenId,
    required String produktName,
    required double menge,
    required String einheit,
  }) async {
    await _client.from('bestandszaehlungen').insert({
      'posten_id': postenId,
      'produkt_name': produktName,
      'menge': menge,
      'einheit': einheit,
    });
  }

  Future<List<Map<String, dynamic>>> ladeBestandHeute(String postenId) async {
    final heute = DateTime.now().toIso8601String().split('T').first;
    final rows = await _client
        .from('bestandszaehlungen')
        .select()
        .eq('posten_id', postenId)
        .eq('gezaehlt_am', heute)
        .order('erstellt_am', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------
  // Defekte
  // ---------------------------------------------------------------------
  Future<String> ladeDefektFotoUrl(String dateiname, Uint8List bytes) async {
    final pfad = '${DateTime.now().millisecondsSinceEpoch}_$dateiname';
    await _client.storage.from('defekt-fotos').uploadBinary(pfad, bytes);
    return _client.storage.from('defekt-fotos').getPublicUrl(pfad);
  }

  Future<void> meldeDefekt({
    required String postenId,
    required String maschine,
    required String beschreibung,
    String? fotoUrl,
  }) async {
    await _client.from('defekte').insert({
      'posten_id': postenId,
      'maschine': maschine,
      'beschreibung': beschreibung,
      'foto_url': fotoUrl,
    });
  }

  Future<List<Defekt>> ladeDefekte(String postenId) async {
    final rows = await _client
        .from('defekte')
        .select()
        .eq('posten_id', postenId)
        .order('gemeldet_am', ascending: false);
    return (rows as List).map((r) => Defekt.fromJson(r as Map<String, dynamic>)).toList();
  }
}
