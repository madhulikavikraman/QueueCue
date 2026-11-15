import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/live.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../game/me_tab.dart';
import 'map_tab.dart';
import 'plan_tab.dart';
import 'qr_tab.dart';

class HomeShell extends ConsumerStatefulWidget {
  final int initialTab;
  const HomeShell({super.key, this.initialTab = 0});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int tab = widget.initialTab;
  bool online = true;
  String? _applied;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri.toString();
    if (uri == _applied) return;
    _applied = uri;
    final t = GoRouterState.of(context).uri.queryParameters['tab'];
    final i = const {'map': 0, 'plan': 1, 'booths': 1, 'quests': 2, 'card': 3, 'cards': 3, 'rolodex': 3, 'me': 4}[t];
    if (i != null) tab = i;
  }

  @override
  void initState() {
    super.initState();
    ref.read(liveProvider).status.listen((s) {
      if (mounted) setState(() => online = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const MapTab(), const PlanTab(), const MeTab(game: true), const CardTab(), const MeTab()];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (!online)
            Container(
              width: double.infinity,
              color: T.warningBg,
              padding: const EdgeInsets.all(T.s2),
              child: const Text(S.offline, textAlign: TextAlign.center, style: TextStyle(color: T.ink, fontSize: T.small)),
            ),
          Expanded(child: IndexedStack(index: tab, children: pages)),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Booths'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Quests'),
          NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'Cards'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
      ),
    );
  }
}
