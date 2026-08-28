import 'package:hive_flutter/hive_flutter.dart';

/// Lokaler Zwischenspeicher (Hive/IndexedDB im Web) für die Daten, die auch
/// ohne Internetverbindung nutzbar sein sollen: Rezepte (nur Lesezugriff),
/// Aufgaben je Posten, und der aktuelle Bestand je Posten. Zusätzlich eine
/// "Outbox" für Änderungen, die offline vorgenommen wurden und bei der
/// nächsten Internetverbindung nachträglich an Supabase übertragen werden.
///
/// Gespeichert werden jeweils die rohen Zeilen genau in der Form, wie sie
/// von Supabase kommen (Map<String, dynamic>) - so bleiben die bestehenden
/// `fromJson`-Fabriken der Modelle unverändert nutzbar, egal ob die Daten
/// gerade frisch vom Netz oder aus dem Cache kommen.
class LocalCache {
  LocalCache._();
  static final LocalCache instance = LocalCache._();

  static const _postenBox = 'cache_posten';
  static const _rezepteBox = 'cache_rezepte';
  static const _aufgabenBox = 'cache_aufgaben';
  static const _bestandProdukteBox = 'cache_bestand_produkte';
  static const _bestandAktuellBox = 'cache_bestand_aktuell';
  static const _outboxBoxName = 'outbox';

  bool _bereit = false;

  Future<void> init() async {
    if (_bereit) return;
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox(_postenBox),
      Hive.openBox(_rezepteBox),
      Hive.openBox(_aufgabenBox),
      Hive.openBox(_bestandProdukteBox),
      Hive.openBox(_bestandAktuellBox),
      Hive.openBox(_outboxBoxName),
    ]);
    _bereit = true;
  }

  // ---------------------------------------------------------------------
  // Posten: wird schon auf dem allerersten Bildschirm (Postenauswahl)
  // gebraucht, bevor überhaupt ein Posten gewählt wurde - muss also als
  // erstes gecacht sein, damit die App offline überhaupt startklar ist.
  // ---------------------------------------------------------------------
  Future<void> postenSpeichern(List<Map<String, dynamic>> rows) =>
      Hive.box(_postenBox).put('liste', rows);

  List<Map<String, dynamic>> postenLaden() =>
      _alsMapListe(Hive.box(_postenBox).get('liste'));

  // ---------------------------------------------------------------------
  // Rezepte (posten-unabhängig, ein gemeinsamer Cache für alle)
  // ---------------------------------------------------------------------
  Future<void> rezepteSpeichern(List<Map<String, dynamic>> rows) =>
      Hive.box(_rezepteBox).put('liste', rows);

  List<Map<String, dynamic>> rezepteLaden() =>
      _alsMapListe(Hive.box(_rezepteBox).get('liste'));

  // ---------------------------------------------------------------------
  // Aufgaben (je Posten)
  // ---------------------------------------------------------------------
  Future<void> aufgabenSpeichern(String postenId, List<Map<String, dynamic>> rows) =>
      Hive.box(_aufgabenBox).put(postenId, rows);

  List<Map<String, dynamic>> aufgabenLaden(String postenId) =>
      _alsMapListe(Hive.box(_aufgabenBox).get(postenId));

  // ---------------------------------------------------------------------
  // Bestand (Produktkatalog gemeinsam, aktuelle Zählungen je Posten)
  // ---------------------------------------------------------------------
  Future<void> bestandProdukteSpeichern(List<Map<String, dynamic>> rows) =>
      Hive.box(_bestandProdukteBox).put('liste', rows);

  List<Map<String, dynamic>> bestandProdukteLaden() =>
      _alsMapListe(Hive.box(_bestandProdukteBox).get('liste'));

  Future<void> bestandAktuellSpeichern(String postenId, List<Map<String, dynamic>> rows) =>
      Hive.box(_bestandAktuellBox).put(postenId, rows);

  List<Map<String, dynamic>> bestandAktuellLaden(String postenId) =>
      _alsMapListe(Hive.box(_bestandAktuellBox).get(postenId));

  // ---------------------------------------------------------------------
  // Outbox: Änderungen, die offline vorgenommen wurden und noch auf ihre
  // Übertragung an Supabase warten. Jeder Eintrag ist ein eigenständiger
  // Auftrag (siehe SyncService.outboxSynchronisieren für die Verarbeitung).
  // ---------------------------------------------------------------------
  Future<void> outboxHinzufuegen(Map<String, dynamic> auftrag) async {
    await Hive.box(_outboxBoxName).add(auftrag);
  }

  /// Schlüssel -> Auftrag, in der Reihenfolge, in der sie angelegt wurden
  /// (wichtig, damit z.B. zwei Zählungen desselben Produkts in der richtigen
  /// Reihenfolge nachgeholt werden).
  Map<int, Map<String, dynamic>> outboxAlle() {
    final box = Hive.box(_outboxBoxName);
    final ergebnis = <int, Map<String, dynamic>>{};
    for (final schluessel in box.keys) {
      if (schluessel is int) {
        ergebnis[schluessel] = _tiefeKarte(box.get(schluessel));
      }
    }
    return ergebnis;
  }

  int get ausstehendeAuftraege => Hive.box(_outboxBoxName).length;

  Future<void> outboxEntfernen(int schluessel) => Hive.box(_outboxBoxName).delete(schluessel);

  // ---------------------------------------------------------------------
  // Hive gibt verschachtelte Maps/Listen beim Auslesen als dynamisch typierte
  // Strukturen zurück (z.B. LinkedHashMap<dynamic, dynamic>) - ein direktes
  // `as Map<String, dynamic>` würde darauf zur Laufzeit fehlschlagen. Diese
  // Hilfsfunktionen wandeln alles rekursiv in sauber typierte Maps/Listen um,
  // damit die bestehenden Modell-Fabriken (fromJson) unverändert funktionieren.
  // ---------------------------------------------------------------------
  List<Map<String, dynamic>> _alsMapListe(dynamic rohwert) {
    if (rohwert is! List) return [];
    return rohwert.map(_tiefeKarte).toList();
  }

  Map<String, dynamic> _tiefeKarte(dynamic wert) {
    if (wert is Map) {
      return wert.map((schluessel, v) => MapEntry(schluessel.toString(), _tiefwert(v)));
    }
    return <String, dynamic>{};
  }

  dynamic _tiefwert(dynamic wert) {
    if (wert is Map) return _tiefeKarte(wert);
    if (wert is List) return wert.map(_tiefwert).toList();
    return wert;
  }
}
