import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';
import '../game/access_dialog.dart';
import 'drop_sheet.dart';
import 'pitch_card.dart';

class StudentBoothPage extends ConsumerStatefulWidget {
  final String boothId;
  final String? joinToken;
  const StudentBoothPage({super.key, required this.boothId, this.joinToken});
  @override
  ConsumerState<StudentBoothPage> createState() => _StudentBoothPageState();
}

class _StudentBoothPageState extends ConsumerState<StudentBoothPage> {
  bool busy = false;

  Api get api => ref.read(apiProvider);

  Future<void> _join(Future<void> Function() reload) async {
    setState(() => busy = true);
    try {
      await api.post('/api/booths/${widget.boothId}/join', {'t': widget.joinToken});
      await reload();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendCard(Future<void> Function() reload) async {
    try {
      final r = await api.post('/api/booths/${widget.boothId}/card');
      if (mounted) toast(context, r['message'] as String);
      await reload();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _leave(Future<void> Function() reload) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave this line?'),
        content: const Text('You lose your place. No points are lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave line')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await api.post('/api/booths/${widget.boothId}/leave');
    if (mounted) toast(context, r['message'] as String);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      fetch: (api) async {
        final b = await api.get('/api/booths/${widget.boothId}/me${widget.joinToken != null ? '?t=${widget.joinToken}' : ''}');
        final me = await api.get('/api/me');
        return {...b, '_me': me};
      },
      listen: (t) => t == 'booth:${widget.boothId}' || t.startsWith('student:') || t == 'fair',
      fallbackPoll: const Duration(seconds: 15),
      builder: (context, d, reload) {
        final b = d['booth'] as Json;
        final line = d['line'] as Json;
        final est = line['estimate'] as Json;
        final inLine = line['in_line'] == true;
        final met = d['met'] as Json?;
        final dropped = d['dropped'] as Json?;
        final closed = d['fair_status'] == 'closed' || b['status'] != 'open';
        final cardSent = d['card_sent'] != null;
        final me = d['_me'] as Json;
        final resumes = ((me['resumes'] as List?) ?? []).cast<Json>();
        final eligible = d['eligible'] == true;
        final reasons = ((d['block_reasons'] as List?) ?? []).cast<String>();

        Widget hero;
        if (met != null) {
          hero = _MetCard(boothId: widget.boothId, met: met, recruiter: b['recruiter_name'] as String?, reload: reload);
        } else if (inLine) {
          hero = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(est['ahead'] == 0 ? S.youAreNext : est['label'] as String,
                style: const TextStyle(fontSize: T.waitHero, fontWeight: FontWeight.w900, height: 1.05, color: T.ink)),
            const SizedBox(height: T.s2),
            Text('${line['ahead']} ahead of you · position ${line['position']} · waited ${line['waited_min']} min',
                style: const TextStyle(fontSize: T.h3, fontWeight: FontWeight.w600)),
            Text('Based on ${est['avg_service_min']} min per conversation at this booth today. Range, not a promise.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: T.s3),
            QueueBlocks(ahead: (line['ahead'] as num).toInt()),
            const SizedBox(height: T.s3),
            const Text('When you are talking with the recruiter, tap "Send my card to the recruiter". They tap Accept and your cards swap.', style: TextStyle(fontSize: T.small)),
          ]);
        } else {
          hero = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(closed ? 'Line closed' : (est['ahead'] == 0 ? 'No wait' : est['label'] as String),
                style: const TextStyle(fontSize: T.waitHero, fontWeight: FontWeight.w900, height: 1.05)),
            const SizedBox(height: T.s2),
            Text(closed ? 'This booth is not taking new people.' : '${line['count']} in line if you join now',
                style: const TextStyle(fontSize: T.h3, fontWeight: FontWeight.w600)),
            if (dropped != null) ...[
              const SizedBox(height: T.s2),
              Pill('Resume dropped at ${hhmm(dropped['at'])}. The recruiter can see it.', fg: T.success, bg: T.successBg, icon: Icons.check),
            ],
          ]);
        }

        return Scaffold(
          appBar: AppBar(leading: const BackOrHome(), 
            title: Text('Booth ${b['number']} · ${b['name']}'),
            actions: [
              IconButton(
                tooltip: S.accessHelp,
                icon: const Icon(Icons.accessibility_new),
                onPressed: () => showAccessDialog(context, ref, boothId: widget.boothId, boothName: b['name'] as String),
              ),
            ],
          ),
          body: PageBody(onRefresh: reload, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${b['category']} · ${b['tagline']}', style: Theme.of(context).textTheme.bodySmall),
                  if (d['reason'] != null) ...[const SizedBox(height: T.s1), Text(d['reason'] as String, style: const TextStyle(fontSize: T.small))],
                  if (!eligible) ...[
                    const SizedBox(height: T.s2),
                    Wrap(spacing: T.s2, children: [for (final r in reasons) Pill(r, fg: T.danger, bg: T.dangerBg, icon: Icons.block)]),
                  ],
                ]),
              ),
              const SizedBox(width: T.s3),
              FitChip(d['fit'] as num?),
            ]),
            const SizedBox(height: T.s4),
            Card(child: Padding(padding: const EdgeInsets.all(T.s4), child: hero)),
            if (cardSent && met == null) ...[
              const SizedBox(height: T.s3),
              Banner2(
                text: 'Card sent at ${hhmm(d['card_sent'])}. When ${b['recruiter_name'] ?? 'the recruiter'} taps Accept, your cards swap and appear on both screens.',
                icon: Icons.hourglass_top,
              ),
            ],
            const SizedBox(height: T.s4),
            PitchCard(boothId: widget.boothId, data: d, reload: reload),
            const SizedBox(height: T.s4),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Open roles at this booth'),
              children: [
                for (final r in ((b['roles'] as List?) ?? []).cast<Json>())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(r['desc'] as String),
                  ),
              ],
            ),
          ]),
          bottomNavigationBar: closed || met != null
              ? null
              : inLine
                  ? BottomAction(
                      child: FilledButton.icon(
                        onPressed: cardSent ? null : () => _sendCard(reload),
                        icon: const Icon(Icons.badge_outlined),
                        label: Text(cardSent ? 'Card sent. Waiting for the recruiter to accept' : 'Send my card to the recruiter'),
                      ),
                      secondary: TextButton(onPressed: () => _leave(reload), child: const Text(S.leaveLine)),
                    )
                  : BottomAction(
                      child: FilledButton.icon(
                        onPressed: busy ? null : () => _join(reload),
                        icon: const Icon(Icons.how_to_reg),
                        label: const Text(S.joinLine),
                      ),
                      above: OutlinedButton.icon(
                        onPressed: cardSent ? null : () => _sendCard(reload),
                        icon: const Icon(Icons.badge_outlined),
                        label: Text(cardSent ? 'Card sent. Waiting for the recruiter' : 'Talking to them now? Send my card'),
                      ),
                      secondary: OutlinedButton.icon(
                        onPressed: () => showDropSheet(context, ref,
                            boothId: widget.boothId,
                            boothName: b['name'] as String,
                            boothNumber: b['number'] as int,
                            resumes: resumes,
                            matchedResumeId: d['resume_id'] as String?,
                            joinToken: widget.joinToken,
                            onDone: reload),
                        icon: const Icon(Icons.send_outlined),
                        label: Text(dropped == null ? S.dropAndGo : 'Update my drop'),
                      ),
                    ),
        );
      },
    );
  }
}

class _MetCard extends ConsumerWidget {
  final String boothId;
  final Json met;
  final String? recruiter;
  final Future<void> Function() reload;
  const _MetCard({required this.boothId, required this.met, required this.recruiter, required this.reload});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.handshake_outlined, color: T.success, size: 32),
          const SizedBox(width: T.s2),
          Expanded(
            child: Text('Met ${recruiter ?? 'the recruiter'} at ${hhmm(met['at'])}. Cards swapped.',
                style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: T.s3),
        const Text('Their contact details are in your Rolodex. Add a note now, while you remember.', style: TextStyle(fontSize: T.small)),
        const SizedBox(height: T.s3),
        Wrap(spacing: T.s2, runSpacing: T.s2, children: [
          if (met['asked_question'] != true)
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(apiProvider).post('/api/me/rolodex/$boothId/asked');
                await reload();
              },
              icon: const Icon(Icons.help_outline),
              label: const Text(S.iAskedQuestion),
            )
          else
            const Pill('You asked your pitch question', fg: T.success, bg: T.successBg, icon: Icons.check),
        ]),
      ]);
}
