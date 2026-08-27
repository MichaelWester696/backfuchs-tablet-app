import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/aufgabe.dart';
import 'local_cache.dart';
import 'sync_service.dart';

/// Kapselt den Aufgaben-Datenfluss für einen Posten offline-fähig:
/// - zeigt beim Start sofort den zuletzt zwischengespeicherten Stand,
/// - folgt danach dem Realtime-Kanal und schreibt jede Aktualisierung in
///   den lokalen Cache,
/// - erlaubt das Abhaken einer Aufgabe auch ohne Internetverbindung: die
///   Änderung ist sofort sichtbar und wird in die Outbox gelegt, falls die
///   Übertragung an Supabase gerade fehlschlägt.
///
/// Eine Instanz gehört zu einem Posten-Bildschirm (siehe AufgabenScreen) und
/// muss mit [dispose] wieder freigegeben werden.
class AufgabenRepository {
  AufgabenRepository(this.postenId);
  final String postenId;

  final SupabaseClient _client = Supabase.instance.client;
  final StreamController<List<Aufgabe>> _controller = StreamController<List<Aufgabe>>.broadcast();
  StreamSubscription? _realtimeAbo;
  VoidCallback? _wiederverbindungAbmelden;
  List<Map<String, dynamic>> _rohdaten = [];
  bool _gestartet = false;

  Stream<List<Aufgabe>> get stream {
    if (!_gestartet) _starten();
    return _controller.stream;
  }

  void _starten() {
    _gestartet = true;
    _rohdaten = LocalCache.instance.aufgabenLaden(postenId);
    _emittieren();
    _realtimeVerbinden();
    _wiederverbindungAbmelden = SyncService.instance.beiWiederverbindung(_realtimeVerbinden);
  }

  void _realtimeVerbinden() {
    _realtimeAbo?.cancel();
    _realtimeAbo = _client
        .from('aufgaben')
        .stream(primaryKey: ['id'])
        .eq('posten_id', postenId)
        .listen(
          (rows) {
            _rohdaten = rows.map((r) => Map<String, dynamic>.from(r)).toList();
            LocalCache.instance.aufgabenSpeichern(postenId, _rohdaten);
            _emittieren();
          },
          onError: (_) {
            // Verbindung verloren o.ä.: den letzten (ggf. lokal geänderten)
            // Stand beibehalten, statt die Anzeige mit einem Fehler abzubrechen.
          },
        );
  }

  void _emittieren() {
    if (!_controller.isClosed) {
      _controller.add(_rohdaten.map((r) => Aufgabe.fromJson(r)).toList());
    }
  }

  /// Markiert eine Aufgabe als erledigt. Wirkt sofort lokal (auch offline);
  /// schlägt die Übertragung fehl, wird sie für die nächste Verbindung in
  /// die Outbox gelegt.
  Future<void> bestaetigen(String aufgabeId) async {
    final erledigtAm = DateTime.now().toUtc().toIso8601String();

    final index = _rohdaten.indexWhere((a) => a['id'] == aufgabeId);
    if (index != -1) {
      _rohdaten[index] = {
        ..._rohdaten[index],
        'status': 'erledigt',
        'erledigt_am': erledigtAm,
      };
      await LocalCache.instance.aufgabenSpeichern(postenId, _rohdaten);
      _emittieren();
    }

    try {
      await _client.from('aufgaben').update({
        'status': 'erledigt',
        'erledigt_am': erledigtAm,
      }).eq('id', aufgabeId);
    } catch (_) {
      await LocalCache.instance.outboxHinzufuegen({
        'type': 'aufgabe_erledigt',
        'aufgabeId': aufgabeId,
        'erledigtAm': erledigtAm,
      });
    }
  }

  void dispose() {
    _realtimeAbo?.cancel();
    _wiederverbindungAbmelden?.call();
    _controller.close();
  }
}
