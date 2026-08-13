import 'package:flutter/material.dart';

/// Corporate Design von Wester's Backfuchs.
class BackfuchsFarben {
  static const dunkelrot = Color(0xFF8B1A1A);
  static const creme = Color(0xFFFAF5EC);
  static const gold = Color(0xFFF0C040);
  static const gruen = Color(0xFF4C8B4C); // für "erledigt" / niedrige Dringlichkeit
  static const rot = Color(0xFFB33A3A); // für hohe Dringlichkeit
}

ThemeData buildBackfuchsTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: BackfuchsFarben.dunkelrot,
      primary: BackfuchsFarben.dunkelrot,
      secondary: BackfuchsFarben.gold,
      surface: BackfuchsFarben.creme,
    ),
    scaffoldBackgroundColor: BackfuchsFarben.creme,
  );

  // Touch-optimiert für Tablets in der Backstube: große Schrift, große Touch-Ziele.
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontSizeFactor: 1.25,
      bodyColor: Colors.black87,
      displayColor: Colors.black87,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: BackfuchsFarben.dunkelrot,
      foregroundColor: Colors.white,
      centerTitle: true,
      toolbarHeight: 72,
      titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BackfuchsFarben.dunkelrot,
        foregroundColor: Colors.white,
        minimumSize: const Size(88, 56),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: BackfuchsFarben.dunkelrot,
      unselectedItemColor: Colors.black45,
      selectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
