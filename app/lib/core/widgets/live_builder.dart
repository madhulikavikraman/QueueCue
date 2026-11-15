import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../api/live.dart';
import 'states.dart';

/// Fetches JSON, refetches when a matching live topic arrives (and on a slow
/// fallback timer), and keeps showing the last good data while refreshing.
class LiveBuilder extends ConsumerStatefulWidget {
  final Future<Json> Function(Api api) fetch;
  final bool Function(String topic) listen;
  final Widget Function(BuildContext context, Json data, Future<void> Function() reload) builder;
  final Duration fallbackPoll;
  final String? emptyTitle;

  const LiveBuilder({
    super.key,
    required this.fetch,
    required this.listen,
    required this.builder,
    this.fallbackPoll = const Duration(seconds: 20),
    this.emptyTitle,
  });

  @override
  ConsumerState<LiveBuilder> createState() => _LiveBuilderState();
}

class _LiveBuilderState extends ConsumerState<LiveBuilder> {
  Json? data;
  Object? error;
  StreamSubscription<Set<String>>? sub;
  Timer? poll;
  bool loading = false;
  bool pending = false;

  @override
  void initState() {
    super.initState();
    reload();
    sub = ref.read(liveProvider).topics.listen((ts) {
      if (ts.contains('*') || ts.any(widget.listen)) reload();
    });
    poll = Timer.periodic(widget.fallbackPoll, (_) => reload());
  }

  @override
  void dispose() {
    sub?.cancel();
    poll?.cancel();
    super.dispose();
  }

  Future<void> reload() async {
    if (loading) {
      pending = true;
      return;
    }
    loading = true;
    try {
      final d = await widget.fetch(ref.read(apiProvider));
      if (!mounted) return;
      setState(() {
        data = d;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e);
    } finally {
      loading = false;
      if (pending && mounted) {
        pending = false;
        unawaited(reload());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data == null && error == null) return const LoadingState();
    if (data == null) return ErrorState(message: '$error', onRetry: reload);
    return widget.builder(context, data!, reload);
  }
}
