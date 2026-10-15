import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models.dart';
import '../providers.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// In-trip chat between passenger and driver.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.orderId, required this.title, required this.myId});
  final String orderId;
  final String title;
  final String myId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<dynamic>? _sub;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = ref.read(realtimeProvider).on('chat.message').listen((e) {
      final m = ChatMessage.fromJson(e.data as Map<String, dynamic>);
      if (m.orderId != widget.orderId || _messages.any((x) => x.id == m.id)) return;
      setState(() => _messages.add(m));
      _toBottom();
    });
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(apiProvider).messages(widget.orderId);
      if (!mounted) return;
      setState(() => _messages
        ..clear()
        ..addAll(list));
      _toBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final m = await ref.read(apiProvider).sendMessage(widget.orderId, body);
      _text.clear();
      if (!_messages.any((x) => x.id == m.id)) setState(() => _messages.add(m));
      _toBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Text(s.t('chat_empty'), style: const TextStyle(color: NomoColors.ink2)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final mine = m.senderId == widget.myId;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
                        decoration: BoxDecoration(
                          color: mine ? cs.onSurface : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(m.body, style: TextStyle(color: mine ? cs.surface : cs.onSurface, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text('${two(m.createdAt.hour)}:${two(m.createdAt.minute)}',
                              style: TextStyle(fontSize: 11, color: (mine ? cs.surface : cs.onSurface).withValues(alpha: 0.6))),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(hintText: s.t('message_hint'), counterText: ''),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: s.t('rate_send'),
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
