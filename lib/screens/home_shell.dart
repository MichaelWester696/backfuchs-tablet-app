import 'dart:async';

import 'package:flutter/material.dart';

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

/// Container mit Bottom-Navigation für die 5 Hauptmodule der App.
class HomeShell extends StatefulWidget {
  final Posten posten;
  const HomeShell({super.key, required this.posten});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

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

    final navItems = istTechnik
        ? const [
            BottomNavigationBarItem(icon: Icon(Icons.build), label: 'Defekte'),
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Nachrichten'),
          ]
        : [
            const BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Aufgaben'),
            if (zeigtRezepte) const BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Rezepte'),
            const BottomNavigationBarItem(icon: Icon(Icons.description), label: 'Backzettel'),
            const BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Nachrichten'),
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

/// Auffälliger, selbstverschwindender Banner, der auf jedem Tablet erscheint,
/// sobald ein bereits geladener Backzettel im Dashboard aktualisiert wurde
/// (nicht beim allerersten Import eines Tages - siehe BackzettelUpdateService).
class _BackzettelAktualisiertBanner extends StatefulWidget {
  const _BackzettelAktualisiertBanner();

  @override
  State<_BackzettelAktualisiertBanner> createState() => _BackzettelAktualisiertBannerState();
}

class _BackzettelAktualisiertBannerState extends State<_BackzettelAktualisiertBanner> {
  bool _sichtbar = false;
  StreamSubscription<String>? _abo;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _abo = BackzettelUpdateService.instance.updates.listen((_) {
      if (!mounted) return;
      setState(() => _sichtbar = true);
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 15), () {
        if (mounted) setState(() => _sichtbar = false);
      });
    });
  }

  @override
  void dispose() {
    _abo?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sichtbar) return const SizedBox.shrink();
    return Material(
      color: BackfuchsFarben.gold,
      child: InkWell(
        onTap: () => setState(() => _sichtbar = false),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.black87, size: 26),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Achtung: Backzettel aktualisiert',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
