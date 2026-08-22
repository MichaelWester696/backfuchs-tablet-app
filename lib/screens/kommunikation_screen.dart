import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/nachricht.dart';
import '../models/posten.dart';
import '../services/supabase_service.dart';

/// Ein Konversationspartner ist entweder ein anderer Posten oder "die Leitung"
/// (Backstubenleiter/Stellvertreterin). Leitung hat keine posten_id (analog
/// zum bestehenden Schema: von_posten_id = NULL bedeutet "kam von der Leitung").
class _Konversationspartner {
  final Posten? posten;
  final bool istLeitung;
  const _Konversationspartner.posten(this.posten) : istLeitung = false;
  const _Konversationspartner.leitung()
      : posten = null,
        istLeitung = true;

  String get name => istLeitung ? 'Leitung' : posten!.name;
  String get id => istLeitung ? '__leitung__' : posten!.id;
}

class KommunikationScreen extends StatefulWidget {
  final Posten posten;
  const KommunikationScreen({super.key, required this.posten});

  @override
  State<KommunikationScreen> createState() => _KommunikationScreenState();
}

class _KommunikationScreenState extends State<KommunikationScreen> {
  late Stream<List<Nachricht>> _stream;
  late Future<List<Posten>> _allePostenFuture;
  _Konversationspartner? _ausgewaehlterPartner;

  @override
  void initState() {
    super.initState();
    _stream = SupabaseService.instance.nachrichtenStream();
    _allePostenFuture = SupabaseService.instance.ladePosten();
  }

  /// Alle Nachrichten, die zwischen "meinem" Posten und dem gegebenen Partner
  /// ausgetauscht wurden - nur diese, keine Nachrichten mit anderen Postens
  /// vermischt.
  bool _gehoertZuThread(Nachricht n, _Konversationspartner partner) {
    final meineId = widget.posten.id;
    if (partner.istLeitung) {
      final ichAnLeitung = n.vonPostenId == meineId && n.zielTyp == 'leitung';
      final leitungAnMich = n.vonPostenId == null && n.zielTyp == 'posten' && n.anPostenId == meineId;
      final leitungAnAlle = n.vonPostenId == null && n.zielTyp == 'leitung' && n.anPostenId == null;
      return ichAnLeitung || leitungAnMich || leitungAnAlle;
    }
    final partnerId = partner.posten!.id;
    final ichAnPartner = n.vonPostenId == meineId && n.zielTyp == 'posten' && n.anPostenId == partnerId;
    final partnerAnMich = n.vonPostenId == partnerId && n.zielTyp == 'posten' && n.anPostenId == meineId;
    return ichAnPartner || partnerAnMich;
  }

  @override
  Widget build(BuildContext context) {
    if (_ausgewaehlterPartner == null) {
      return _Konversationsliste(
        meinPosten: widget.posten,
        allePostenFuture: _allePostenFuture,
        stream: _stream,
        gehoertZuThread: _gehoertZuThread,
        onAuswahl: (p) => setState(() => _ausgewaehlterPartner = p),
      );
    }
    return _ChatThread(
      meinPosten: widget.posten,
      partner: _ausgewaehlterPartner!,
      stream: _stream,
      gehoertZuThread: _gehoertZuThread,
      onZurueck: () => setState(() => _ausgewaehlterPartner = null),
    );
  }
}

class _Konversationsliste extends StatelessWidget {
  final Posten meinPosten;
  final Future<List<Posten>> allePostenFuture;
  final Stream<List<Nachricht>> stream;
  final bool Function(Nachricht, _Konversationspartner) gehoertZuThread;
  final void Function(_Konversationspartner) onAuswahl;

  const _Konversationsliste({
    required this.meinPosten,
    required this.allePostenFuture,
    required this.stream,
    required this.gehoertZuThread,
    required this.onAuswahl,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Posten>>(
      future: allePostenFuture,
      builder: (context, postenSnapshot) {
        if (!postenSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final andere = postenSnapshot.data!.where((p) => p.id != meinPosten.id).toList();
        final partner = <_Konversationspartner>[
          const _Konversationspartner.leitung(),
          ...andere.map((p) => _Konversationspartner.posten(p)),
        ];

        return StreamBuilder<List<Nachricht>>(
          stream: stream,
          builder: (context, nachrichtenSnapshot) {
            final alleNachrichten = nachrichtenSnapshot.data ?? [];

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: partner.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = partner[i];
                final threadNachrichten = alleNachrichten.where((n) => gehoertZuThread(n, p)).toList()
                  ..sort((a, b) => b.erstelltAm.compareTo(a.erstelltAm));
                final letzte = threadNachrichten.isNotEmpty ? threadNachrichten.first : null;

                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(p.istLeitung ? Icons.supervisor_account : Icons.groups),
                  ),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: letzte != null
                      ? Text(letzte.text, maxLines: 1, overflow: TextOverflow.ellipsis)
                      : const Text('Noch keine Nachrichten', style: TextStyle(color: Colors.black45)),
                  trailing: letzte != null
                      ? Text(
                          DateFormat('dd.MM. HH:mm').format(letzte.erstelltAm.toLocal()),
                          style: const TextStyle(fontSize: 12, color: Colors.black45),
                        )
                      : null,
                  onTap: () => onAuswahl(p),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ChatThread extends StatefulWidget {
  final Posten meinPosten;
  final _Konversationspartner partner;
  final Stream<List<Nachricht>> stream;
  final bool Function(Nachricht, _Konversationspartner) gehoertZuThread;
  final VoidCallback onZurueck;

  const _ChatThread({
    required this.meinPosten,
    required this.partner,
    required this.stream,
    required this.gehoertZuThread,
    required this.onZurueck,
  });

  @override
  State<_ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<_ChatThread> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _senden() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await SupabaseService.instance.sendeNachricht(
      vonPostenId: widget.meinPosten.id,
      zielTyp: widget.partner.istLeitung ? 'leitung' : 'posten',
      anPostenId: widget.partner.istLeitung ? null : widget.partner.posten!.id,
      text: text,
    );
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).appBarTheme.backgroundColor,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: widget.onZurueck,
                  ),
                  Text(
                    widget.partner.name,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Nachricht>>(
            stream: widget.stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final nachrichten = snapshot.data!.where((n) => widget.gehoertZuThread(n, widget.partner)).toList()
                ..sort((a, b) => a.erstelltAm.compareTo(b.erstelltAm));
              if (nachrichten.isEmpty) {
                return const Center(child: Text('Noch keine Nachrichten in dieser Konversation.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: nachrichten.length,
                itemBuilder: (context, i) {
                  final n = nachrichten[i];
                  final vonMir = n.vonPostenId == widget.meinPosten.id;
                  return Align(
                    alignment: vonMir ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: vonMir ? Colors.amber.shade100 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.text, style: const TextStyle(fontSize: 17)),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd.MM. HH:mm').format(n.erstelltAm.toLocal()),
                            style: const TextStyle(fontSize: 12, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(hintText: 'Nachricht an ${widget.partner.name}...'),
                    onSubmitted: (_) => _senden(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _senden, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
