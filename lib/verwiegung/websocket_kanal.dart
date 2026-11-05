import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_waage.dart';

/// Öffnet die WebSocket-Verbindung zum Waagen-Knoten. Wirft, wenn der Knoten
/// nicht erreichbar ist (die Waage versucht es dann nach einer Pause neu).
Future<WaagenKanal> verbindeWebSocket(Uri adresse) async {
  final kanal = WebSocketChannel.connect(adresse);
  try {
    await kanal.ready;
  } catch (_) {
    await kanal.sink.close();
    rethrow;
  }
  return _WebSocketKanal(kanal);
}

class _WebSocketKanal implements WaagenKanal {
  final WebSocketChannel _kanal;

  _WebSocketKanal(this._kanal);

  @override
  Stream<String> get nachrichten => _kanal.stream.map((daten) {
        if (daten is String) return daten;
        if (daten is List<int>) return utf8.decode(daten, allowMalformed: true);
        return '';
      });

  @override
  Future<void> schliessen() async {
    await _kanal.sink.close();
  }
}
