import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'token_store.dart';

class RealtimeEvent {
  RealtimeEvent(this.type, this.data);
  final String type;
  final dynamic data;
}

/// Keeps one WebSocket open to the backend and reconnects with backoff.
///
/// Events: order.updated, offer.new, offer.cancelled, driver.location,
/// chat.message, driver.status.
class RealtimeClient {
  RealtimeClient(this.tokens, {this.refreshToken});

  final TokenStore tokens;

  /// Called before reconnecting so an expired access token gets renewed.
  final Future<void> Function()? refreshToken;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _wanted = false;

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<bool> get connection => _connected.stream;
  bool get isConnected => _channel != null;

  Stream<RealtimeEvent> on(String type) => events.where((e) => e.type == type);

  void connect() {
    _wanted = true;
    if (_channel != null) return;
    _open();
  }

  Future<void> _open() async {
    final token = tokens.access;
    if (!_wanted || token == null) return;
    try {
      final ch = WebSocketChannel.connect(Uri.parse('${NomoConfig.wsUrl}?token=${Uri.encodeComponent(token)}'));
      await ch.ready;
      _channel = ch;
      _attempt = 0;
      _connected.add(true);
      _sub = ch.stream.listen(
        (raw) {
          try {
            final m = jsonDecode(raw as String) as Map<String, dynamic>;
            _events.add(RealtimeEvent(m['type'] as String, m['data']));
          } catch (_) {}
        },
        onDone: _dropped,
        onError: (_) => _dropped(),
        cancelOnError: true,
      );
    } catch (_) {
      _dropped();
    }
  }

  void _dropped() {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _connected.add(false);
    if (!_wanted) return;
    _retry?.cancel();
    final delay = Duration(milliseconds: min(30000, 500 * pow(2, _attempt).toInt()));
    _attempt++;
    _retry = Timer(delay, () async {
      if (_attempt > 1 && refreshToken != null) {
        try {
          await refreshToken!();
        } catch (_) {}
      }
      _open();
    });
  }

  /// Sends a JSON message; returns false when offline.
  bool send(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) return false;
    ch.sink.add(jsonEncode(msg));
    return true;
  }

  void disconnect() {
    _wanted = false;
    _retry?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _events.close();
    _connected.close();
  }
}
