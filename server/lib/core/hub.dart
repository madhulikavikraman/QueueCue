import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Live updates. The server only says WHAT changed (topics); clients refetch.
/// Simple and robust: a missed message is healed by the next one or by the
/// client's periodic refresh.
class Hub {
  final _clients = <WebSocketChannel>{};
  final _pending = <String>{};
  Timer? _flush;

  void add(WebSocketChannel ch) {
    _clients.add(ch);
    ch.stream.listen((_) {}, onDone: () => _clients.remove(ch), onError: (_) => _clients.remove(ch));
    ch.sink.add(jsonEncode({'t': 'hello'}));
  }

  int get count => _clients.length;

  /// Topics: 'fair', 'booth:<id>', 'student:<id>', 'job:<id>', 'organizer'.
  /// Coalesced over 120 ms so bursts (simulate crowd, close fair) stay cheap.
  void changed(Iterable<String> topics) {
    _pending.addAll(topics);
    _flush ??= Timer(const Duration(milliseconds: 120), () {
      final msg = jsonEncode({'t': 'changed', 'topics': _pending.toList()});
      _pending.clear();
      _flush = null;
      for (final c in _clients.toList()) {
        try {
          c.sink.add(msg);
        } catch (_) {
          _clients.remove(c);
        }
      }
    });
  }
}
