import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/live.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import 'student_alerts.dart';

/// Student app frame: bottom tabs over a stateful shell (each tab keeps its
/// scroll position and inputs; each has its own URL).
class HomeShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  const HomeShell({super.key, required this.shell});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool online = true;

  @override
  void initState() {
    super.initState();
    ref.read(liveProvider).status.listen((s) {
      if (mounted) setState(() => online = s);
    });
  }

  @override
  Widget build(BuildContext context) => StudentAlerts(
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              if (!online)
                Container(
                  width: double.infinity,
                  color: T.warningBg,
                  padding: const EdgeInsets.all(T.s2),
                  child: const Text(S.offline, textAlign: TextAlign.center, style: TextStyle(color: T.ink, fontSize: T.small)),
                ),
              Expanded(child: widget.shell),
            ]),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: widget.shell.currentIndex,
            // Tapping the current tab again returns it to its top.
            onDestinationSelected: (i) => widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
              NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Booths'),
              NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Quests'),
              NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'Cards'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
            ],
          ),
        ),
      );
}
