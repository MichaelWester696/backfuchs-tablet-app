import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../verwiegung/waagen_dienst.dart';
import '../verwiegung/websocket_kanal.dart';
import 'waagen_einstellungen.dart';

/// Die gemeinsame Verbindung der App zum Waagen-Knoten (siehe [WaagenDienst]).
final waagenDienst = WaagenDienst(
  kanalFabrik: verbindeWebSocket,
  adresseLaden: WaagenEinstellungen.ladeAdresse,
);

/// Hält die Verbindung offen, solange die App im Vordergrund ist: beim Start
/// verbinden, im Hintergrund trennen (der Knoten bedient nur wenige Tablets
/// gleichzeitig) und beim Zurückkehren neu verbinden. Im Browser (https) kann
/// die App keine Verbindung ins lokale Netz öffnen, dort passiert nichts.
class WaagenVerbindungsWaechter with WidgetsBindingObserver {
  WaagenVerbindungsWaechter._();
  static final instance = WaagenVerbindungsWaechter._();

  bool _aktiv = false;

  void starten() {
    if (kIsWeb || _aktiv) return;
    _aktiv = true;
    WidgetsBinding.instance.addObserver(this);
    waagenDienst.starten();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState zustand) {
    switch (zustand) {
      case AppLifecycleState.resumed:
        waagenDienst.starten();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        waagenDienst.anhalten();
      case AppLifecycleState.inactive:
        break; // nur kurz überdeckt (Dialog, Berechtigungsabfrage): Verbindung behalten
    }
  }
}
