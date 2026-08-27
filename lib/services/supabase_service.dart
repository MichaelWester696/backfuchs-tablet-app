import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/aufgabe.dart';
import '../models/bestand_produkt.dart';
import '../models/defekt.dart';
import '../models/nachricht.dart';
import '../models/posten.dart';
import '../models/rezept.dart';
import 'offline/local_cache.dart';

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

  // Der Realtime-Stream und das Abhaken einer Aufgabe laufen offline-fähig
  // über AufgabenRepository (siehe services/offline/aufgaben_repository.dart):
  // dort werden Änderungen sofort lokal übernommen und, falls die
  // Übertragung gerade fehlschlägt, für die nächste Verbindung in die
  // Outbox gelegt.

  // ---------------------------------------------------------------------
  // Rezepte
  // ---------------------------------------------------------------------
  /// Rezepte sind nur lesend vom Tablet aus zugänglich, daher genügt hier ein
  /// einfacher Lese-Cache ohne Outbox: bei Erfolg wird der (ungefilterte)
  /// Gesamtbestand im lokalen Cache aktualisiert, bei einem Netzwerkfehler
  /// wird stattdessen daraus gefiltert - so bleiben Rezepte auch offline
  /// durchsuchbar und einzeln abrufbar (z.B. für den "Zum Rezept"-Sprung).
  Future<List<Rezept>> sucheRezepte(String suchbegriff) async {
    final begriff = suchbegriff.trim();
    try {
      var query = _client.from('rezepte').select();
      if (begriff.isNotEmpty) {
        query = query.ilike('name', '%$begriff%');
      }
      final rows = await query.order('name');
      final liste = (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      if (begriff.isEmpty) {
        await LocalCache.instance.rezepteSpeichern(liste);
      }
      return liste.map((r) => Rezept.fromJson(r)).toList();
    } catch (_) {
      final zwischengespeichert = LocalCache.instance.rezepteLaden();
      final gefiltert = begriff.isEmpty
          ? zwischengespeichert
          : zwischengespeichert
              .where((r) => (r['name'] as String? ?? '').toLowerCase().contains(begriff.toLowerCase()))
              .toList();
      gefiltert.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
      return gefiltert.map((r) => Rezept.fromJson(r)).toList();
    }
  }

  Future<Rezept?> ladeRezeptById(String id) async {
    try {
      final row = await _client.from('rezepte').select().eq('id', id).maybeSingle();
      return row == null ? null : Rezept.fromJson(row);
    } catch (_) {
      final treffer = LocalCache.instance.rezepteLaden().where((r) => r['id'] == id);
      return treffer.isEmpty ? null : Rezept.fromJson(treffer.first);
    }
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
  /// Fester, im Dashboard gepflegter Produktkatalog für die Bestandszählung.
  Future<List<BestandProdukt>> ladeBestandProdukte() async {
    try {
      final rows = await _client
          .from('bestand_produkte')
          .select()
          .eq('aktiv', true)
          .order('reihenfolge');
      final liste = (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      await LocalCache.instance.bestandProdukteSpeichern(liste);
      return liste.map((r) => BestandProdukt.fromJson(r)).toList();
    } catch (_) {
      return LocalCache.instance.bestandProdukteLaden().map((r) => BestandProdukt.fromJson(r)).toList();
    }
  }

  /// Erfasst eine Zählung. Es wird immer nur der neueste Wert je
  /// (Posten, Produkt, Träger) gehalten - ein erneutes Speichern überschreibt
  /// die vorherige Zählung für denselben Träger, statt eine neue Zeile
  /// anzulegen. Blech und Diele desselben Produkts sind unabhängige Zeilen.
  ///
  /// Wirkt sofort lokal (auch offline); schlägt die Übertragung fehl, wird
  /// sie für die nächste Verbindung in die Outbox gelegt.
  Future<void> erfasseBestandszaehlung({
    required String postenId,
    required BestandProdukt produkt,
    required Traeger traeger,
    required double menge,
  }) async {
    final jetzt = DateTime.now().toUtc().toIso8601String();

    final zwischengespeichert = LocalCache.instance.bestandAktuellLaden(postenId)
      ..removeWhere((r) => r['produkt_id'] == produkt.id && r['traeger'] == traeger.wert)
      ..add({
        'produkt_id': produkt.id,
        'produkt_name': produkt.name,
        'traeger': traeger.wert,
        'menge': menge,
        'aktualisiert_am': jetzt,
        'bestand_produkte': {'name': produkt.name, 'reihenfolge': produkt.reihenfolge},
      });
    await LocalCache.instance.bestandAktuellSpeichern(postenId, zwischengespeichert);

    try {
      await _client.from('bestandszaehlungen').upsert(
        {
          'posten_id': postenId,
          'produkt_id': produkt.id,
          'produkt_name': produkt.name,
          'traeger': traeger.wert,
          'menge': menge,
          'aktualisiert_am': jetzt,
        },
        onConflict: 'posten_id,produkt_id,traeger',
      );
    } catch (_) {
      await LocalCache.instance.outboxHinzufuegen({
        'type': 'bestand_zaehlung',
        'postenId': postenId,
        'produktId': produkt.id,
        'produktName': produkt.name,
        'traeger': traeger.wert,
        'menge': menge,
        'aktualisiertAm': jetzt,
      });
    }
  }

  /// Aktueller Bestand eines Postens - eine Zeile je Produkt und Träger
  /// (immer der neueste Wert, siehe Upsert oben).
  Future<List<BestandEintrag>> ladeBestandAktuell(String postenId) async {
    try {
      final rows = await _client
          .from('bestandszaehlungen')
          .select('*, bestand_produkte(name, reihenfolge)')
          .eq('posten_id', postenId)
          .not('produkt_id', 'is', null);
      final liste = (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      await LocalCache.instance.bestandAktuellSpeichern(postenId, liste);
      return _bestandEintraegeSortiert(liste);
    } catch (_) {
      return _bestandEintraegeSortiert(LocalCache.instance.bestandAktuellLaden(postenId));
    }
  }

  List<BestandEintrag> _bestandEintraegeSortiert(List<Map<String, dynamic>> rows) {
    final eintraege = rows.map((r) => BestandEintrag.fromJson(r)).toList();
    eintraege.sort((a, b) {
      final nameVergleich = a.produktName.compareTo(b.produktName);
      return nameVergleich != 0 ? nameVergleich : a.traeger.compareTo(b.traeger);
    });
    return eintraege;
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

  /// Alle Defekte über alle Posten hinweg (für die Technik-Verwaltungsansicht).
  Future<List<Defekt>> ladeAlleDefekte() async {
    final rows = await _client
        .from('defekte')
        .select('*, posten:posten_id(name)')
        .order('gemeldet_am');
    return (rows as List).map((r) => Defekt.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> markiereDefektErledigt(String defektId) async {
    await _client.from('defekte').update({
      'status': 'behoben',
      'behoben_am': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', defektId);
  }

  // ---------------------------------------------------------------------
  // Schichtabschluss
  // ---------------------------------------------------------------------
  Future<bool> pruefeSchichtAbgeschlossen(String postenId) async {
    final heute = DateTime.now().toIso8601String().split('T').first;
    final row = await _client
        .from('schicht_abschluesse')
        .select('id')
        .eq('posten_id', postenId)
        .eq('datum', heute)
        .maybeSingle();
    return row != null;
  }

  Future<void> schliesseSchichtAb(String postenId) async {
    final heute = DateTime.now().toIso8601String().split('T').first;
    await _client.from('schicht_abschluesse').upsert(
      {'posten_id': postenId, 'datum': heute},
      onConflict: 'posten_id,datum',
    );
  }

  // ---------------------------------------------------------------------
  // Backstubenleitung-Zugang (PIN-geschützt)
  // ---------------------------------------------------------------------
  /// Prüft den eingegebenen PIN über die serverseitige Funktion
  /// `pruefe_leitung_pin` (Migration 0003). Die Tabelle app_einstellungen
  /// selbst ist für Clients nicht mehr lesbar, damit der PIN nicht per
  /// direktem REST-Query abgefragt werden kann.
  Future<bool> pruefeLeitungsPin(String eingegebenerPin) async {
    final ergebnis = await _client.rpc(
      'pruefe_leitung_pin',
      params: {'eingabe': eingegebenerPin},
    );
    return ergebnis as bool;
  }

  /// PIN-Prüfung für den Posten "Technik" (eigener PIN, ebenfalls über eine
  /// serverseitige Funktion, siehe Migration 0008).
  Future<bool> pruefeTechnikPin(String eingegebenerPin) async {
    final ergebnis = await _client.rpc(
      'pruefe_technik_pin',
      params: {'eingabe': eingegebenerPin},
    );
    return ergebnis as bool;
  }
}
