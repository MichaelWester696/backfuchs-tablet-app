import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Beobachtet die "backzettel"-Tabelle über den gesamten App-Lauf hinweg
/// (unabhängig davon, welcher Tab gerade offen ist) und erkennt echte
/// Aktualisierungen (nicht den ersten Import) anhand des hochgeladen_am-
/// Zeitstempels je Arbeitsdatum. Wird für den auf allen Tablets sichtbaren
/// "Backzettel aktualisiert"-Hinweis in HomeShell genutzt.
class BackzettelUpdateService {
  BackzettelUpdateService._();
  static final BackzettelUpdateService instance = BackzettelUpdateService._();

  final _controller = StreamController<String>.broadcast(); // emittiert das betroffene Arbeitsdatum
  Stream<String> get updates => _controller.stream;

  final Map<String, DateTime> _bekannteZeitstempel = {};
  StreamSubscription? _abo;
  bool _gestartet = false;

  void start() {
    if (_gestartet) return;
    _gestartet = true;
    _abo = Supabase.instance.client
        .from('backzettel')
        .stream(primaryKey: ['id'])
        .listen(
          (rows) {
            for (final r in rows) {
              final arbeitsdatum = r['arbeitsdatum'] as String?;
              final zeitstempelRoh = r['hochgeladen_am'] as String?;
              if (arbeitsdatum == null || zeitstempelRoh == null) continue;
              final zeitstempel = DateTime.tryParse(zeitstempelRoh);
              if (zeitstempel == null) continue;

              final bekannt = _bekannteZeitstempel[arbeitsdatum];
              if (bekannt != null && zeitstempel.isAfter(bekannt)) {
                _controller.add(arbeitsdatum);
              }
              _bekannteZeitstempel[arbeitsdatum] = zeitstempel;
            }
          },
          onError: (_) {
            // Verbindung verloren o.ä. - der Realtime-Kanal von supabase_flutter
            // versucht selbst automatisch, sich wiederzuverbinden.
          },
        );
  }
}
