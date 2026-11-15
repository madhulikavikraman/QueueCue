import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../onboarding/onboarding_page.dart';
import 'access_dialog.dart';

/// game: true = Quests tab (level, side quests, badges, leaderboard).
/// game: false = Me tab (profile, resumes, recap, Fair Play, help, sign out).
class MeTab extends ConsumerWidget {
  final bool game;
  const MeTab({super.key, this.game = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) => LiveBuilder(
        fetch: (api) async => {
          'me': await api.get('/api/me'),
          'game': await api.get('/api/me/game'),
          'lb': await api.get('/api/me/leaderboard'),
        },
        listen: (t) => t.startsWith('student:') || t == 'fair',
        builder: (context, d, reload) {
          final me = d['me'] as Json;
          final g = d['game'] as Json;
          final lb = d['lb'] as Json;
          final lvl = g['level'] as Json;
          final pts = (g['points'] as num).toInt();
          final nextMin = (lvl['next_min'] as num?)?.toInt();
          final curMin = (lvl['min'] as num).toInt();
          final quests = ((g['quests'] as List?) ?? []).cast<Json>();
          final badges = ((g['badges'] as List?) ?? []).cast<Json>();
          final api = ref.read(apiProvider);
          return PageBody(onRefresh: reload, children: [
            Row(children: [
              PixelAvatar(me['avatar'] as String, size: 48),
              const SizedBox(width: T.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(me['name'] as String, style: Theme.of(context).textTheme.headlineSmall),
                  Text('${me['degree'] ?? ''} ${me['major']}', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
            if (game) ...[
            const SizedBox(height: T.s4),
            Card(
              color: T.ink,
              child: Padding(
                padding: const EdgeInsets.all(T.s4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${lvl['name']}'.toUpperCase(), style: const TextStyle(color: T.accent, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 2)),
                    const Spacer(),
                    Text('$pts', style: const TextStyle(color: T.bg, fontWeight: FontWeight.w900, fontSize: 28)),
                    const SizedBox(width: 6),
                    const Text(S.points, style: TextStyle(color: T.bg, fontSize: T.small)),
                  ]),
                  const SizedBox(height: T.s3),
                  LinearProgressIndicator(
                    value: nextMin == null ? 1 : ((pts - curMin) / (nextMin - curMin)).clamp(0.0, 1.0),
                    minHeight: 10,
                    color: T.accent,
                    backgroundColor: T.muted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  const SizedBox(height: T.s2),
                  Text(
                    nextMin == null ? 'Top level.' : '${lvl['to_next']} to ${lvl['next']}. ${lvl['how']}',
                    style: const TextStyle(color: T.bg, fontSize: T.small),
                  ),
                  if ((g['pending_points'] as num) > 0)
                    Text('+${g['pending_points']} pending (follow-ups are awarded the next day)', style: const TextStyle(color: T.accent, fontSize: T.small)),
                ]),
              ),
            ),
            const SizedBox(height: T.s2),
            Text('Rookie 0 · Regular 20 · Networker 60 · Closer 100', style: Theme.of(context).textTheme.bodySmall),
            SectionTitle(S.quests, sub: 'Three, picked for you.'),
            Card(
              child: Column(children: [
                for (final q in quests)
                  ListTile(
                    leading: Icon(q['done'] == true ? Icons.check_box : Icons.check_box_outline_blank, color: q['done'] == true ? T.success : T.muted),
                    title: Text(q['title'] as String),
                    trailing: q['id'] == 'paperless' && q['done'] != true
                        ? TextButton(
                            onPressed: () async {
                              await api.post('/api/me/paperless');
                              await reload();
                            },
                            child: const Text("I didn't print"),
                          )
                        : null,
                  ),
              ]),
            ),
            SectionTitle(S.badges, sub: 'Unlocked once.'),
            Wrap(alignment: WrapAlignment.center, spacing: T.s3, runSpacing: T.s3, children: [
              for (final b in badges)
                SizedBox(
                  width: 96,
                  child: Column(children: [
                    PixelBadge(b['id'] as String, earned: b['earned'] == true),
                    const SizedBox(height: T.s1),
                    Text(b['name'] as String, textAlign: TextAlign.center, style: TextStyle(fontSize: T.tiny, fontWeight: FontWeight.w700, color: b['earned'] == true ? T.ink : T.muted)),
                    Text(b['desc'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: T.muted)),
                  ]),
                ),
            ]),
            SectionTitle(S.leaderboard, sub: 'Opt-in. Friends only. Campus view shows only your percentile.'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(S.leaderboardOptIn),
              value: lb['opted_in'] == true,
              onChanged: (v) async {
                await api.patch('/api/me', {'leaderboard_opt_in': v});
                await reload();
              },
            ),
            if (lb['opted_in'] == true) ...[
              Card(
                child: Column(children: [
                  for (final (i, f) in ((lb['friends'] as List).cast<Json>()).indexed)
                    ListTile(
                      dense: true,
                      tileColor: f['me'] == true ? T.accent.withValues(alpha: 0.3) : null,
                      leading: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      title: Row(children: [PixelAvatar(f['avatar'] as String, size: 24), const SizedBox(width: T.s2), Expanded(child: Text(f['name'] as String))]),
                      subtitle: Text(f['level'] as String),
                      trailing: Text('${f['points']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
              const SizedBox(height: T.s2),
              Text('Campus: you are at the ${lb['campus_percentile']}th percentile of ${lb['campus_size']} checked-in students.',
                  style: const TextStyle(fontSize: T.small)),
            ],
            const SizedBox(height: T.s2),
            const Text(S.pointsNeverRecruiters, style: TextStyle(fontSize: T.small, color: T.muted)),
            ],
            if (!game) ...[
            const SizedBox(height: T.s4),
            Card(
              child: Column(children: [
                ListTile(leading: const Icon(Icons.summarize_outlined), title: const Text(S.recap), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/recap')),
                ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: const Text(S.fairPlay),
                    subtitle: const Text('Your top 3 fits get your resume at close'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/fairplay')),
                ListTile(
                    leading: const Icon(Icons.balance_outlined),
                    title: const Text(S.whyHere),
                    subtitle: const Text('Your Fit, Effort and Score on each recruiter list'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/why')),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Resumes and voice'),
                  subtitle: Text('${(me['resumes'] as List).length} resumes · ${me['has_voice'] == true ? 'Voice Profile saved' : 'no Voice Profile'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingPage(startStep: 1))),
                ),
                ListTile(leading: const Icon(Icons.accessibility_new), title: const Text(S.accessHelp), onTap: () => showAccessDialog(context, ref)),
                ListTile(leading: const Icon(Icons.info_outline), title: const Text(S.about), onTap: () => context.push('/about')),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(me['persona'] != null ? 'Switch demo student' : 'Sign out on this phone'),
                  onTap: () async {
                    await ref.read(sessionProvider.notifier).set(null);
                    if (context.mounted) context.go('/');
                  },
                ),
              ]),
            ),
            ],
          ]);
        },
      );
}
