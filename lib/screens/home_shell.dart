import 'dart:async';

import 'package:flutter/material.dart';

import '../models/nachricht.dart';
import '../models/posten.dart';
import '../services/backzettel_update_service.dart';
import '../services/offline/sync_service.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'aufgaben_screen.dart';
import 'backzettel_screen.dart';
import 'bestand_screen.dart';
import 'defekt_screen.dart';
import 'kommunikation_screen.dart';
import 'posten_login_screen.dart';
import 'rezepte_screen.dart';

/// Icon für den "Nachrichten"-Tab mit rotem Punkt, sobald für diesen Posten
/// ungelesene, eingehende Nachrichten vorliegen (siehe
/// istEingehendUndUngelesen in kommunikation_screen.dart - dieselbe
/// Definition wird auch beim Markieren als gelesen im Chat-Thread benutzt).
/// Bekommt den Stream von außen übergeben (siehe _HomeShellState), statt ihn
/// selbst zu erzeugen - sonst würde bei jedem Tab-Wechsel (jeder Rebuild von
/// HomeShell) eine neue Supabase-Realtime-Subscription aufgebaut.
class _NachrichtenTabIcon extends StatelessWidget {
  final Stream<List<Nachricht>> stream;
  final String meinPostenId;
  const _NachrichtenTabIcon({required this.stream, required this.meinPostenId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Nachricht>>(
      stream: stream,
      builder: (context, snapshot) {
        final ungelesen = (snapshot.data ?? []).any((n) => istEingehendUndUngelesen(n, meinPostenId));
        return Badge(
          isLabelVisible: ungelesen,
          backgroundColor: Colors.red,
          smallSize: 10,
          child: const Icon(Icons.chat_bubble),
        );
      },
    );
  }
}

/// Container mit Bottom-Navigation für die 5 Hauptmodule der App.
class HomeShell extends StatefulWidget {
  final Posten posten;
  const HomeShell({super.key, required this.posten});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final Stream<List<Nachricht>> _nachrichtenStream;

  @override
  void initState() {
    super.initState();
    if (widget.posten.name != 'Technik') {
      // Rezepte im Hintergrund vorladen (und dabei lokal zwischenspeichern),
      // damit sie auch offline abrufbar sind, ohne den Rezepte-Tab zuvor
      // manuell geöffnet haben zu müssen.
      SupabaseService.instance.sucheRezepte('');
    }
    // Läuft für die gesamte App-Sitzung, unabhängig vom aktiven Tab, damit
    // der "Backzettel aktualisiert"-Hinweis auf jedem Tablet erscheint.
    BackzettelUpdateService.instance.start();
    // Einmalig erzeugen und wiederverwenden (siehe _NachrichtenTabIcon).
    _nachrichtenStream = SupabaseService.instance.nachrichtenStream();
  }

  void _zurPostenauswahl() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PostenLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Der Posten "Technik" verwaltet Defekte über alle Posten hinweg und
    // braucht Rezepte/Bestand/Aufgaben nicht - daher nur Defekte + Nachrichten.
    final istTechnik = widget.posten.name == 'Technik';

    final zeigtRezepte = widget.posten.zeigtRezepte;

    final screens = istTechnik
        ? [
            DefektScreen(posten: widget.posten),
            KommunikationScreen(posten: widget.posten),
          ]
        : [
            AufgabenScreen(posten: widget.posten),
            if (zeigtRezepte) RezepteScreen(posten: widget.posten),
            const BackzettelScreen(),
            KommunikationScreen(posten: widget.posten),
            BestandScreen(posten: widget.posten),
            DefektScreen(posten: widget.posten),
          ];

    final nachrichtenTabItem = BottomNavigationBarItem(
      icon: _NachrichtenTabIcon(stream: _nachrichtenStream, meinPostenId: widget.posten.id),
      label: 'Nachrichten',
    );

    final navItems = istTechnik
        ? [
            const BottomNavigationBarItem(icon: Icon(Icons.build), label: 'Defekte'),
            nachrichtenTabItem,
          ]
        : [
            const BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Aufgaben'),
            if (zeigtRezepte) const BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Rezepte'),
            const BottomNavigationBarItem(icon: Icon(Icons.description), label: 'Backzettel'),
            nachrichtenTabItem,
            const BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Bestand'),
            const BottomNavigationBarItem(icon: Icon(Icons.build), label: 'Defekte'),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.posten.name),
        leading: IconButton(
          tooltip: 'Posten wechseln',
          icon: const Icon(Icons.switch_account),
          onPressed: _zurPostenauswahl,
        ),
      ),
      body: Column(
        children: [
          const _BackzettelAktualisiertBanner(),
          const _OfflineLeiste(),
          Expanded(child: IndexedStack(index: _index, children: screens)),
        ],
      ),
      // SafeArea sorgt dafür, dass die Leiste auf einem iPhone ohne Home-Button
      // (X und neuer) oberhalb der unteren Wisch-Geste-Zone bleibt, statt darunter
      // zu verschwinden bzw. mit ihr zu überlappen.
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: navItems,
        ),
      ),
    );
  }
}

/// Schmaler Hinweisbalken, der erscheint, sobald die Internetverbindung
/// fehlt bzw. gerade wiederhergestellt und synchronisiert wird. Im Normalfall
/// (online, nichts zu tun) nimmt er keinen Platz ein.
class _OfflineLeiste extends StatelessWidget {
  const _OfflineLeiste();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: SyncService.instance.statusStream,
      initialData: SyncService.instance.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.online;
        if (status == SyncStatus.online) return const SizedBox.shrink();

        final istOffline = status == SyncStatus.offline;
        return Container(
          width: double.infinity,
          color: istOffline ? Colors.black87 : BackfuchsFarben.gold,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                istOffline ? Icons.cloud_off : Icons.sync,
                size: 16,
                color: istOffline ? Colors.white : Colors.black87,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  istOffline
                      ? 'Offline – Änderungen werden gespeichert und bei Wiederverbindung übertragen.'
                      : 'Verbindung wiederhergestellt – wird synchronisiert …',
                  style: TextStyle(fontSize: 13, color: istOffline ? Colors.white : Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Unsichtbarer Listener, der auf jedem Tablet einen Bestätigungsdialog
/// öffnet, sobald ein bereits geladener Backzettel im Dashboard aktualisiert
/// wurde (nicht beim allerersten Import eines Tages - siehe
/// BackzettelUpdateService). Sitzt in HomeShell oberhalb der Tab-Inhalte,
/// läuft also unabhängig davon, welcher Tab gerade aktiv ist. Der Dialog
/// muss aktiv bestätigt werden (weder Antippen außerhalb noch der
/// Zurück-Button schließen ihn), damit die Meldung nicht unbemerkt
/// verschwindet.
class _BackzettelAktualisiertBanner extends StatefulWidget {
  const _BackzettelAktualisiertBanner();

  @override
  State<_BackzettelAktualisiertBanner> createState() => _BackzettelAktualisiertBannerState();
}

class _BackzettelAktualisiertBannerState extends State<_BackzettelAktualisiertBanner> {
  StreamSubscription<String>? _abo;
  bool _dialogOffen = false;

  @override
  void initState() {
    super.initState();
    _abo = BackzettelUpdateService.instance.updates.listen((_) => _dialogAnzeigen());
  }

  Future<void> _dialogAnzeigen() async {
    // Verhindert gestapelte Dialoge, falls kurz hintereinander mehrere
    // Aktualisierungen eintreffen, während der vorherige Dialog noch offen ist.
    if (!mounted || _dialogOffen) return;
    _dialogOffen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: BackfuchsFarben.gold,
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.black87, size: 32),
          title: const Text(
            'Achtung: Backzettel aktualisiert',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          content: const Text(
            'Der Backzettel für ein bereits geladenes Datum wurde soeben geändert. '
            'Bitte den aktuellen Stand im Backzettel-Tab prüfen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black87),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                child: Text('Verstanden'),
              ),
            ),
          ],
        ),
      ),
    );
    _dialogOffen = false;
  }

  @override
  void dispose() {
    _abo?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
