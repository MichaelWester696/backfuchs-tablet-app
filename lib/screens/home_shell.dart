import 'package:flutter/material.dart';

import '../models/posten.dart';
import 'aufgaben_screen.dart';
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
      body: IndexedStack(index: _index, children: screens),
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
