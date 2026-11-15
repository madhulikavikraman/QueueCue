import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';

class PlanTab extends ConsumerWidget {
  const PlanTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LiveBuilder(
      fetch: (api) async {
        final me = await api.get('/api/me');
        final plan = await api.get('/api/me/plan');
        final fp = me['fair_status'] == 'closed' ? await api.get('/api/me/fairplay') : null;
        return {'me': me, 'plan': plan, 'fp': fp};
      },
      listen: (t) => t.startsWith('student:') || t.startsWith('booth:') || t == 'fair' || t.startsWith('job:'),
      builder: (context, d, reload) {
        final me = d['me'] as Json;
        final plan = d['plan'] as Json;
        final items = ((plan['items'] as List?) ?? []).cast<Json>();
        final job = plan['job'] as Json?;
        final fp = d['fp'] as Json?;
        final current = me['current_line'] as String?;
        return Scaffold(
          body: PageBody(onRefresh: reload, children: [
            Row(children: [
              PixelAvatar(me['avatar'] as String, size: 36),
              const SizedBox(width: T.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('All booths', style: Theme.of(context).textTheme.headlineSmall),
                  Text('${me['name']} · ${me['major']} · ${me['work_auth_label']}', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
            const SizedBox(height: T.s3),
            if (fp != null)
              Banner2(
                text: fp['message'] as String,
                icon: Icons.verified_outlined,
                color: T.success,
                bg: T.successBg,
                action: TextButton(onPressed: () => context.push('/recap'), child: const Text('Fair Recap')),
              ),
            if (me['has_voice'] != true)
              Padding(
                padding: const EdgeInsets.only(top: T.s2),
                child: Banner2(
                  text: 'No Voice Profile yet, so pitches are plainer. Add it in Me > Resumes and voice.',
                  color: T.warning,
                  bg: T.warningBg,
                ),
              ),
            if (current != null) ...[
              const SizedBox(height: T.s2),
              _CurrentLine(boothId: current, items: items),
            ],
            if (job != null) ...[
              const SizedBox(height: T.s3),
              Card(child: Padding(padding: const EdgeInsets.all(T.s4), child: JobProgress(jobId: job['id'] as String, onDone: (_) => reload()))),
            ],
            SectionTitle('Booths, best fit first', sub: S.neverHidden),
            if (items.isEmpty) const EmptyState(icon: Icons.storefront_outlined, title: 'No booths loaded'),
            for (final it in items) Padding(padding: const EdgeInsets.only(bottom: T.s3), child: BoothPlanCard(item: it)),
          ]),
          bottomNavigationBar: me['fair_status'] == 'closed'
              ? BottomAction(child: FilledButton(onPressed: () => context.push('/recap'), child: const Text('See my Fair Recap')))
              : null
        );
      },
    );
  }
}

class _CurrentLine extends StatelessWidget {
  final String boothId;
  final List<Json> items;
  const _CurrentLine({required this.boothId, required this.items});
  @override
  Widget build(BuildContext context) {
    final it = items.where((x) => (x['booth'] as Json)['id'] == boothId).firstOrNull;
    if (it == null) return const SizedBox();
    final line = it['line'] as Json;
    final est = line['estimate'] as Json;
    return Card(
      color: T.accent,
      child: InkWell(
        onTap: () => context.push('/b/$boothId'),
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Row(children: [
            const Icon(Icons.hourglass_top_rounded, color: T.onAccent),
            const SizedBox(width: T.s3),
            Expanded(
              child: Text('In line at ${(it['booth'] as Json)['name']}: ${line['ahead']} ahead, ${est['label']}',
                  style: const TextStyle(color: T.onAccent, fontWeight: FontWeight.w700)),
            ),
            const Icon(Icons.chevron_right, color: T.onAccent),
          ]),
        ),
      ),
    );
  }
}

class BoothPlanCard extends StatelessWidget {
  final Json item;
  const BoothPlanCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final b = item['booth'] as Json;
    final line = item['line'] as Json;
    final est = line['estimate'] as Json;
    final eligible = item['eligible'] == true;
    final reasons = ((item['block_reasons'] as List?) ?? []).cast<String>();
    final closed = b['status'] != 'open';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(T.radius),
        onTap: () => context.push('/b/${b['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${item['rank']}. ${b['name']}', style: Theme.of(context).textTheme.titleMedium),
                  Text('Booth ${b['number']} · ${b['category']}', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              FitChip(item['fit'] as num?),
            ]),
            if (item['reason'] != null) ...[
              const SizedBox(height: T.s2),
              Text(item['reason'] as String, style: const TextStyle(fontSize: T.small)),
            ],
            if (item['resume_label'] != null) ...[
              const SizedBox(height: T.s2),
              Text.rich(TextSpan(children: [
                const TextSpan(text: '${S.useResume}: ', style: TextStyle(color: T.muted, fontSize: T.small)),
                TextSpan(text: '${item['resume_label']} resume', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: T.small)),
                if (item['resume_reason'] != null)
                  TextSpan(text: '. ${item['resume_reason']}', style: const TextStyle(color: T.muted, fontSize: T.small)),
              ])),
            ],
            const SizedBox(height: T.s3),
            Wrap(spacing: T.s2, runSpacing: T.s2, children: [
              if (!eligible) for (final r in reasons) Pill(r, fg: T.danger, bg: T.dangerBg, icon: Icons.block),
              if (item['citizenship_required'] == true && eligible) const Pill(S.citizensOnly, fg: T.warning, bg: T.warningBg),
              Pill('${S.sponsors}: ${item['sponsors']}',
                  fg: item['sponsors'] == 'yes' ? T.success : (item['sponsors'] == 'no' ? T.danger : T.muted),
                  bg: item['sponsors'] == 'yes' ? T.successBg : (item['sponsors'] == 'no' ? T.dangerBg : T.surfaceAlt)),
              Pill('${S.hiresMajor}: ${item['major_flag']}',
                  fg: item['major_flag'] == 'yes' ? T.success : (item['major_flag'] == 'no' ? T.danger : T.warning),
                  bg: item['major_flag'] == 'yes' ? T.successBg : (item['major_flag'] == 'no' ? T.dangerBg : T.warningBg)),
              if (item['off_beaten'] == true) const Pill(S.offBeaten, fg: T.onAccent, bg: T.accent, icon: Icons.alt_route),
            ]),
            const SizedBox(height: T.s3),
            Row(children: [
              const Icon(Icons.people_alt_outlined, size: 16, color: T.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  closed
                      ? 'Line closed'
                      : line['in_line'] == true
                          ? 'You are in line: ${line['ahead']} ahead, ${est['label']}'
                          : '${line['count']} in line · ${est['ahead'] == 0 ? 'no wait' : est['label']}',
                  style: TextStyle(fontSize: T.small, color: line['in_line'] == true ? T.brand : T.muted, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: T.muted),
            ]),
          ]),
        ),
      ),
    );
  }
}
