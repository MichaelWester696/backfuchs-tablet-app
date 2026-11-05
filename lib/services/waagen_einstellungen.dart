import 'package:shared_preferences/shared_preferences.dart';

/// Einstellungen der Waagenanbindung, pro Gerät gespeichert.
///
/// Der Waagen-Knoten bekommt im Router eine feste Adresse (DHCP-Reservierung).
/// Der Name `waage.local` funktioniert auf Android nicht zuverlässig, deshalb
/// ist die IP-Adresse der Standard.
class WaagenEinstellungen {
  static const standardAdresse = 'ws://192.168.2.108:81';
  static const _schluesselAdresse = 'waagen_knoten_adresse';
  static const _schluesselSimulation = 'waagen_simulation';

  /// Prüft eine Eingabe und liefert die Adresse oder null, wenn sie ungültig ist.
  /// "192.168.2.108" und "192.168.2.108:81" werden zu "ws://192.168.2.108:81" ergänzt.
  static Uri? pruefeAdresse(String eingabe) {
    var text = eingabe.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'ws://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != 'ws' && uri.scheme != 'wss') || uri.host.isEmpty) return null;
    return uri.hasPort ? uri : uri.replace(port: 81);
  }

  static Future<Uri> ladeAdresse() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gespeichert = prefs.getString(_schluesselAdresse);
      final uri = gespeichert == null ? null : pruefeAdresse(gespeichert);
      if (uri != null) return uri;
    } catch (_) {}
    return Uri.parse(standardAdresse);
  }

  static Future<void> speichereAdresse(Uri adresse) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_schluesselAdresse, adresse.toString());
  }

  /// Simulation statt echter Waage (zum Ausprobieren ohne Hardware).
  static Future<bool> ladeSimulation({required bool standard}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_schluesselSimulation) ?? standard;
    } catch (_) {
      return standard;
    }
  }

  static Future<void> speichereSimulation(bool an) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_schluesselSimulation, an);
  }
}
