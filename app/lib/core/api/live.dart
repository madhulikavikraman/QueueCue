import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

/// One WebSocket per device. The server only says which topics changed; the
/// screens that care refetch. Reconnects with backoff.
class Live {
  final Api api;
  final _topics = StreamController<Set<String>>.broadcast();
  final _status = StreamController<bool>.broadcast();
  WebSocketChannel? _ch;
  bool connected = false;
  int _attempt = 0;
  bool _disposed = false;

  Live(this.api) {
    _connect();
  }

  Stream<Set<String>> get topics => _topics.stream;
  Stream<bool> get status => _status.stream;

  void _connect() {
    if (_disposed) return;
    try {
      final ch = WebSocketChannel.connect(Uri.parse(api.wsUrl()));
      _ch = ch;
      ch.stream.listen((msg) {
        if (!connected) {
          connected = true;
          _attempt = 0;
          _status.add(true);
          _topics.add({'*'}); // refetch after (re)connect
        }
        try {
          final j = jsonDecode(msg as String) as Map<String, dynamic>;
          if (j['t'] == 'changed') _topics.add(((j['topics'] as List?) ?? const []).cast<String>().toSet());
        } catch (_) {}
      }, onDone: _retry, onError: (_) => _retry(), cancelOnError: true);
    } catch (_) {
      _retry();
    }
  }

  void _retry() {
    if (connected) {
      connected = false;
      _status.add(false);
    }
    _ch = null;
    final delay = Duration(milliseconds: (500 * (1 << _attempt.clamp(0, 5))).clamp(500, 10000));
    _attempt++;
    Timer(delay, _connect);
  }

  void dispose() {
    _disposed = true;
    _ch?.sink.close();
    _topics.close();
    _status.close();
  }
}

final liveProvider = Provider<Live>((ref) {
  final l = Live(ref.read(apiProvider));
  ref.onDispose(l.dispose);
  return l;
});
