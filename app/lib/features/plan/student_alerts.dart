import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/api/live.dart';
import '../../core/design/tokens.dart';
import 'how_it_works.dart';

/// Watches for moments the student must not miss, anywhere in the app:
/// a recruiter accepted their card, a friend accepted, or they reached the
/// front of the line. Each shows once (remembered across reloads).
class StudentAlerts extends ConsumerStatefulWidget {
  final Widget child;
  const StudentAlerts({super.key, required this.child});
  @override
  ConsumerState<StudentAlerts> createState() => _StudentAlertsState();
}

class _StudentAlertsState extends ConsumerState<StudentAlerts> {
  StreamSubscription? sub;
  Timer? poll;
  bool busy = false;
  int? lastAhead;

  String get _who => ref.read(sessionProvider) ?? '';

  @override
  void initState() {
    super.initState();
    sub = ref.read(liveProvider).topics.listen((t) {
      if (t.contains('*') || t.any((x) => x.startsWith('student:') || x.startsWith('booth:'))) _check();
    });
    poll = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    _check(initial: true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final k = 'qq_intro_$_who';
      if (_who.isEmpty || await Prefs.get(k) != null || !mounted) return;
      await Prefs.set(k, '1');
      if (mounted) await showHowItWorks(context);
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    poll?.cancel();
    super.dispose();
  }

  Future<void> _check({bool initial = false}) async {
    if (busy || _who.isEmpty) return;
    busy = true;
    try {
      final a = await ref.read(apiProvider).get('/api/me/alerts');
      if (!mounted) return;
      final ex = a['exchange'] as Json?;
      final fr = a['friend'] as Json?;
      final exKey = 'qq_seen_ex_$_who', frKey = 'qq_seen_fr_$_who';
      final seenEx = await Prefs.get(exKey);
      final seenFr = await Prefs.get(frKey);
      // First run for this student: remember what already happened, show nothing.
      if (seenEx == null) {
        await Prefs.set(exKey, '${ex?['id'] ?? 0}');
      } else if (ex != null && '${ex['id']}' != seenEx) {
        await Prefs.set(exKey, '${ex['id']}');
        _celebrate('Cards swapped', '${ex['name']} (${ex['company']}) accepted your card. Their card is in your rolodex.', '/cards');
      }
      if (seenFr == null) {
        await Prefs.set(frKey, '${fr?['id'] ?? 0}');
      } else if (fr != null && '${fr['id']}' != seenFr) {
        await Prefs.set(frKey, '${fr['id']}');
        _celebrate('New friend card', '${fr['name']} accepted. You both have each other\'s card now.', '/cards');
      }
      final line = a['line'] as Json?;
      final ahead = (line?['ahead'] as num?)?.toInt();
      if (!initial && ahead == 0 && lastAhead != null && lastAhead! > 0) {
        HapticFeedback.heavyImpact();
        _celebrate("You're next", 'At ${line!['name']}. Walk up and tap "Send my card to the recruiter".', '/b/${line['booth_id']}');
      }
      lastAhead = ahead;
    } catch (_) {
      // Alerts are best-effort; the screens themselves still update.
    } finally {
      busy = false;
    }
  }

  void _celebrate(String title, String body, String goTo) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.celebration_outlined, color: T.brand, size: 40),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(body, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              // Tabs are switched to (go); other screens open on top (push).
              if (goTo.startsWith('/b/')) {
                context.push(goTo);
              } else {
                context.go(goTo);
              }
            },
            child: const Text('Show me'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
