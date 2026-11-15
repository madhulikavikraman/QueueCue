import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';

class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});
  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  Json? demo;
  Json? fair;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    try {
      final f = await api.get('/api/fair');
      final d = await api.get('/api/demo/personas');
      if (mounted) setState(() {
        fair = f;
        demo = d;
      });
    } catch (e) {
      if (mounted) setState(() => fair = {'error': '$e'});
    }
  }

  Future<void> _rememberPending() async {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith('/join/') || loc.startsWith('/b/')) await Prefs.set('qq_pending', loc);
  }

  @override
  Widget build(BuildContext context) {
    final personas = ((demo?['personas'] as List?) ?? const []).cast<Map>();
    return Scaffold(
      body: SafeArea(
        child: PageBody(children: [
          const SizedBox(height: T.s5),
          Center(child: Image.asset('assets/brand/logo_3d_512.png', width: 190)),
          const SizedBox(height: T.s5),
          Text(S.welcomeTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: T.s2),
          const Text(S.welcomeBody, style: TextStyle(color: T.muted)),
          if (fair != null && fair!['name'] != null) ...[
            const SizedBox(height: T.s4),
            Banner2(
              text: '${fair!['name']} · ${fair!['venue']} · ${(fair!['booths'] as List).length} employers'
                  '${fair!['status'] == 'closed' ? ' · closed' : ''}',
              icon: Icons.storefront_outlined,
            ),
          ],
          if (fair?['error'] != null) ...[const SizedBox(height: T.s4), ErrorState(message: '${fair!['error']}', onRetry: _load)],
          const SizedBox(height: T.s5),
          const SectionTitle('Who are you today?'),
          _RoleCard(
            icon: Icons.school_outlined,
            title: "I'm a student",
            body: 'See the map, join lines, get your pitch, swap cards.',
            onTap: () async {
              await _rememberPending();
              if (context.mounted) context.go('/onboarding');
            },
            action: 'Set up in 2 minutes',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => context.go('/login'), child: const Text('Already a student here? Sign in')),
          ),
          const SizedBox(height: T.s3),
          _RoleCard(
            icon: Icons.badge_outlined,
            title: "I'm a recruiter",
            body: 'Your line, quick ratings, card swaps and your shortlist.',
            onTap: () => context.go('/recruiter'),
            action: 'Recruiter sign-in',
          ),
          if (personas.isNotEmpty) ...[
            SectionTitle(S.demoTitle, sub: 'Jump in as a seeded student.'),
            for (final p in personas)
              Padding(
                padding: const EdgeInsets.only(bottom: T.s2),
                child: Card(
                  child: ListTile(
                    leading: PixelAvatar(p['avatar'] as String),
                    title: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(p['label'] as String),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await ref.read(recruiterProvider.notifier).set(null);
                      await ref.read(sessionProvider.notifier).set(p['token'] as String);
                      final pending = await Prefs.get('qq_pending');
                      if (!context.mounted) return;
                      context.go(pending != null && pending.isNotEmpty ? pending : '/');
                    },
                  ),
                ),
              ),
          ],
          const SizedBox(height: T.s5),
          Wrap(spacing: T.s2, runSpacing: T.s2, children: [
            OutlinedButton.icon(
                onPressed: () => context.go('/organizer${demo?['organizer_key'] != null ? '?org=${demo!['organizer_key']}' : ''}'),
                icon: const Icon(Icons.map_outlined),
                label: const Text(S.organizer)),
            TextButton(onPressed: () => context.go('/links'), child: const Text('All screens')),
            TextButton(onPressed: () => context.go('/about'), child: const Text(S.about)),
          ]),
        ]),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;
  const _RoleCard({required this.icon, required this.title, required this.body, required this.action, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(T.radius),
          child: Padding(
            padding: const EdgeInsets.all(T.s4),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: T.accent, borderRadius: BorderRadius.circular(T.radius), border: Border.all(color: T.ink, width: 2)),
                child: Icon(icon, color: T.ink, size: 30),
              ),
              const SizedBox(width: T.s4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w800)),
                  Text(body, style: const TextStyle(color: T.muted, fontSize: T.small)),
                  const SizedBox(height: T.s2),
                  Text('$action  →', style: const TextStyle(color: T.brand, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
