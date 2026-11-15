import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/rolodex.dart';

/// Demo Mode: ten students, the same three recruiters, and the Fair Play
/// points engine at work. Tap a student to flip through their rolodex.
class ShowcasePage extends ConsumerWidget {
  const ShowcasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(leading: const BackOrHome(), title: const Text('Fair Play points: live demo')),
        body: LiveBuilder(
          fetch: (api) => api.get('/api/demo/showcase'),
          listen: (t) => t.startsWith('student:') || t.startsWith('booth:'),
          builder: (context, d, reload) {
            final students = ((d['students'] as List?) ?? []).cast<Json>();
            final recruiters = ((d['recruiters'] as List?) ?? []).cast<Json>();
            final maxPts = students.isEmpty ? 1 : students.map((s) => s['points'] as int).reduce((a, b) => a > b ? a : b).clamp(1, 9999);
            return PageBody(onRefresh: reload, children: [
              const Text(
                'Ten students, three recruiters. Points come from the real rules: verified conversations, questions asked, '
                'notes, follow-ups and well-matched drops. Volume is capped and points never affect what recruiters see.',
                style: TextStyle(color: T.muted),
              ),
              const SizedBox(height: T.s3),
              Wrap(spacing: T.s2, runSpacing: T.s2, children: [
                for (final r in recruiters) Pill('${r['name']} · ${r['company']}', icon: Icons.badge_outlined, bg: T.accent, fg: T.onAccent),
              ]),
              const SizedBox(height: T.s4),
              for (final (i, s) in students.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: T.s2),
                  child: _Row(rank: i + 1, s: s, maxPts: maxPts),
                ),
            ]);
          },
        ),
      );
}

class _Row extends ConsumerWidget {
  final int rank;
  final Json s;
  final int maxPts;
  const _Row({required this.rank, required this.s, required this.maxPts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = s['card'] as Json;
    final lvl = s['level'] as Json;
    final met = ((s['met'] as List?) ?? []).cast<Json>();
    final dropped = ((s['dropped'] as List?) ?? []).cast<Json>();
    final pts = s['points'] as int;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(T.radius),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Detail(s: s))),
        child: Padding(
          padding: const EdgeInsets.all(T.s3),
          child: Row(children: [
            SizedBox(width: 28, child: Text('$rank', style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w900, color: T.muted))),
            PixelAvatar(c['avatar'] as String, size: 44),
            const SizedBox(width: T.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: T.h3))),
                  Text('#${c['number']}', style: const TextStyle(fontFamily: 'monospace', color: T.muted, fontSize: T.small)),
                ]),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pts / maxPts),
                  duration: Duration(milliseconds: 700 + rank * 90),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 10, color: T.brand, backgroundColor: T.surfaceAlt),
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('$pts pts', style: const TextStyle(fontWeight: FontWeight.w900, color: T.brand)),
                  if ((s['pending'] as int) > 0) Text('+${s['pending']} tomorrow', style: const TextStyle(fontSize: T.tiny, color: T.muted)),
                  Pill('${lvl['name']}', bg: T.accent, fg: T.onAccent),
                  Pill('met ${met.length}', icon: Icons.handshake_outlined),
                  if (dropped.isNotEmpty) Pill('${dropped.length} drops', icon: Icons.send_outlined),
                  for (final b in ((s['badges'] as List?) ?? [])) PixelBadge('$b', earned: true, size: 20),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right, color: T.muted),
          ]),
        ),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  final Json s;
  const _Detail({required this.s});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = s['card'] as Json;
    final met = ((s['met'] as List?) ?? []).cast<Json>();
    final ledger = ((s['ledger'] as List?) ?? []).cast<Json>();
    final dropped = ((s['dropped'] as List?) ?? []).cast<Json>();
    return Scaffold(
      appBar: AppBar(title: Text('${c['name']}')),
      body: PageBody(children: [
        Row(children: [
          PixelAvatar(c['avatar'] as String, size: 52),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['points']} Fair Play points', style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w900)),
              Text('${(s['level'] as Json)['name']} · card #${c['number']} · ${s['friends']} friends', style: const TextStyle(color: T.muted)),
            ]),
          ),
        ]),
        const SectionTitle('Rolodex', sub: 'Cards collected from recruiters. Swipe or tap to flip.'),
        RolodexWheel(cards: met, autoplay: met.length > 1),
        const SectionTitle('Booths visited'),
        Wrap(spacing: T.s2, runSpacing: T.s2, children: [
          for (final m in met) Pill('Tent ${m['booth_number']} · ${m['company']} · talked', icon: Icons.handshake_outlined, bg: T.successBg, fg: T.success),
          for (final d in dropped) Pill('Tent ${d['number']} · ${d['name']} · resume dropped', icon: Icons.send_outlined),
          if (met.isEmpty && dropped.isEmpty) const Text('None yet.', style: TextStyle(color: T.muted)),
        ]),
        const SectionTitle('How the points add up'),
        Card(
          child: Column(children: [
            for (final l in ledger)
              ListTile(
                dense: true,
                title: Text('${l['rule']}'),
                subtitle: l['booth'] != null ? Text('${l['booth']}') : null,
                trailing: Text(l['pending'] == true ? '+${l['points']} tomorrow' : '+${l['points']}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: l['pending'] == true ? T.muted : T.success)),
              ),
            if (ledger.isEmpty) const ListTile(title: Text('No points yet. Drops at low-fit booths earn 0 by design.')),
          ]),
        ),
        const SizedBox(height: T.s4),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(recruiterProvider.notifier).set(null);
            await ref.read(sessionProvider.notifier).set(s['token'] as String);
            if (context.mounted) context.go('/cards');
          },
          icon: const Icon(Icons.login),
          label: Text('Sign in as ${(c['name'] as String).split(' ').first}'),
        ),
      ]),
    );
  }
}
