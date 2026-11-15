import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';

/// One shareable screen. Facts and two specific suggestions; no generic praise.
class RecapPage extends ConsumerWidget {
  const RecapPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(leading: const BackOrHome(), title: const Text(S.recap)),
        body: LiveBuilder(
          fetch: (api) => api.get('/api/me/recap'),
          listen: (t) => t.startsWith('student:') || t == 'fair',
          builder: (context, r, reload) {
            final del = r['resumes_delivered'] as Json;
            final lvl = r['level'] as Json;
            final badges = ((r['badges'] as List?) ?? []).cast<Json>();
            final sugg = ((r['suggestions'] as List?) ?? []).cast<String>();
            final best = r['best_fit'] as Json?;
            String shareText() => [
                  '${r['name']}: ${S.recap}',
                  '${r['conversations']} conversations · ${del['total']} resumes delivered (${del['drops']} drops, ${del['fair_play']} Fair Play, ${del['line_credit']} line credit)',
                  '~${r['minutes_saved']} min saved vs. standing in every line',
                  if (best != null) 'Best fit: ${best['name']} (${best['fit_pct']})',
                  'Level: ${lvl['name']} · ${r['points']} ${S.points}',
                  'Badges: ${badges.map((b) => b['name']).join(', ')}',
                  S.tagline,
                ].join('\n');
            return PageBody(onRefresh: reload, children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(T.s5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      PixelAvatar(r['avatar'] as String, size: 44),
                      const SizedBox(width: T.s3),
                      Expanded(child: Text(r['name'] as String, style: Theme.of(context).textTheme.headlineSmall)),
                      Pill('${lvl['name']}', fg: T.onAccent, bg: T.accent),
                    ]),
                    if (r['fair_closed'] != true) ...[
                      const SizedBox(height: T.s3),
                      const Banner2(text: 'The fair is still open. Numbers update live; Fair Play matches are added at close.'),
                    ],
                    const SizedBox(height: T.s4),
                    _Stat('${r['conversations']}', 'conversations confirmed by recruiters', sub: (r['conversation_booths'] as List).join(', ')),
                    _Stat('${del['total']}', 'resumes delivered',
                        sub: '${del['drops']} drop${del['drops'] == 1 ? '' : 's'} · ${del['fair_play']} Fair Play match${del['fair_play'] == 1 ? '' : 'es'} · ${del['line_credit']} line credit'),
                    _Stat('~${r['minutes_saved']} min', 'estimated time saved versus standing in every line',
                        sub: '${r['minutes_in_line']} min actually spent in lines'),
                    if (best != null) _Stat('${best['fit_pct']}', 'best fit: ${best['name']}'),
                    _Stat('${r['points']}', '${S.points} · level ${lvl['name']}',
                        sub: (r['pending_points'] as num) > 0 ? '+${r['pending_points']} arriving tomorrow' : null),
                    const SizedBox(height: T.s3),
                    Wrap(spacing: T.s3, runSpacing: T.s3, children: [
                      for (final b in badges)
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          PixelBadge(b['id'] as String, earned: true, size: 36),
                          Text(b['name'] as String, style: const TextStyle(fontSize: 10.5)),
                        ]),
                      if (badges.isEmpty) const Text('No badges yet.', style: TextStyle(color: T.muted)),
                    ]),
                  ]),
                ),
              ),
              SectionTitle('Next time', sub: 'Two specific things from today.'),
              for (final s in sugg)
                Padding(
                  padding: const EdgeInsets.only(bottom: T.s2),
                  child: Banner2(text: s, icon: Icons.lightbulb_outline, color: T.warning, bg: T.warningBg),
                ),
              const SizedBox(height: T.s4),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: shareText()));
                  if (context.mounted) toast(context, 'Recap copied. Paste it anywhere.');
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Share recap'),
              ),
            ]);
          },
        ),
      );
}

class _Stat extends StatelessWidget {
  final String big;
  final String label;
  final String? sub;
  const _Stat(this.big, this.label, {this.sub});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: T.s3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 96, child: Text(big, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: T.brand))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (sub != null && sub!.isNotEmpty) Text(sub!, style: const TextStyle(fontSize: T.small, color: T.muted)),
            ]),
          ),
        ]),
      );
}
