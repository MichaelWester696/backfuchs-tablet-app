import 'package:flutter/material.dart';

import '../models/posten.dart';
import 'aufgaben_screen.dart';
import 'bestand_screen.dart';
import 'defekt_screen.dart';
import 'kommunikation_screen.dart';
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
  Widget build(BuildContext context) {
    final screens = [
      AufgabenScreen(posten: widget.posten),
      RezepteScreen(posten: widget.posten),
      KommunikationScreen(posten: widget.posten),
      BestandScreen(posten: widget.posten),
      DefektScreen(posten: widget.posten),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(widget.posten.name)),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Aufgaben'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Rezepte'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Nachrichten'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Bestand'),
          BottomNavigationBarItem(icon: Icon(Icons.build), label: 'Defekte'),
        ],
      ),
    );
  }
}
