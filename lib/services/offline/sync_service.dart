import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_cache.dart';

enum SyncStatus { online, offline, synchronisiert }

/// Beobachtet die Internetverbindung des Geräts und kümmert sich darum, dass
/// Änderungen, die offline gemacht wurden (siehe [LocalCache.outboxHinzufuegen]),
/// bei Wiederverbindung automatisch nachgeholt werden.
///
/// Andere Teile der App (z.B. der Aufgaben-Realtime-Kanal) können sich über
/// [beiWiederverbindung] benachrichtigen lassen, um z.B. ihren eigenen Stand
/// neu zu laden.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus _status = SyncStatus.online;
  SyncStatus get status => _status;

  StreamSubscription<List<ConnectivityResult>>? _verbindungsAbo;
  final List<VoidCallback> _wiederverbindungsListener = [];

  Future<void> init() async {
    await LocalCache.instance.init();

    final anfangsStatus = await Connectivity().checkConnectivity();
    _statusSetzen(_istVerbunden(anfangsStatus) ? SyncStatus.online : SyncStatus.offline);

    _verbindungsAbo = Connectivity().onConnectivityChanged.listen((ergebnis) {
      final verbunden = _istVerbunden(ergebnis);
      final warOffline = _status == SyncStatus.offline;
      if (verbunden && warOffline) {
        _wiederverbindungBehandeln();
      } else if (!verbunden) {
        _statusSetzen(SyncStatus.offline);
      }
    });
  }

  bool _istVerbunden(List<ConnectivityResult> ergebnis) =>
      ergebnis.any((r) => r != ConnectivityResult.none);

  void _statusSetzen(SyncStatus status) {
    _status = status;
    _statusController.add(status);
  }

  /// Registriert eine Funktion, die bei Wiederverbindung aufgerufen wird
  /// (z.B. um einen Realtime-Kanal neu zu verbinden). Gibt eine Funktion
  /// zurück, mit der man sich wieder abmelden kann (im dispose() aufrufen).
  VoidCallback beiWiederverbindung(VoidCallback fn) {
    _wiederverbindungsListener.add(fn);
    return () => _wiederverbindungsListener.remove(fn);
  }

  Future<void> _wiederverbindungBehandeln() async {
    _statusSetzen(SyncStatus.synchronisiert);
    for (final fn in List<VoidCallback>.of(_wiederverbindungsListener)) {
      try {
        fn();
      } catch (_) {
        // Ein einzelner fehlerhafter Listener soll die anderen nicht stören.
      }
    }
    await outboxSynchronisieren();
    _statusSetzen(SyncStatus.online);
  }

  /// Arbeitet die Outbox in Reihenfolge ab. Bricht bei einem Fehler ab
  /// (bleibt für den nächsten Versuch stehen), statt die Reihenfolge zu
  /// verletzen oder spätere Änderungen vor früheren zu übertragen.
  Future<void> outboxSynchronisieren() async {
    final auftraege = LocalCache.instance.outboxAlle();
    final client = Supabase.instance.client;
    for (final eintrag in auftraege.entries) {
      try {
        await _auftragAusfuehren(client, eintrag.value);
        await LocalCache.instance.outboxEntfernen(eintrag.key);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _auftragAusfuehren(SupabaseClient client, Map<String, dynamic> auftrag) async {
    switch (auftrag['type']) {
      case 'aufgabe_erledigt':
        await client.from('aufgaben').update({
          'status': 'erledigt',
          'erledigt_am': auftrag['erledigtAm'],
        }).eq('id', auftrag['aufgabeId']);
        return;
      case 'bestand_zaehlung':
        await client.from('bestandszaehlungen').upsert(
          {
            'posten_id': auftrag['postenId'],
            'produkt_id': auftrag['produktId'],
            'produkt_name': auftrag['produktName'],
            'traeger': auftrag['traeger'],
            'menge': auftrag['menge'],
            'aktualisiert_am': auftrag['aktualisiertAm'],
          },
          onConflict: 'posten_id,produkt_id,traeger',
        );
        return;
    }
  }

  void dispose() {
    _verbindungsAbo?.cancel();
    _statusController.close();
  }
}
