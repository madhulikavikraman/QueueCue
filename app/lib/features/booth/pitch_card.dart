import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';

/// The pitch brief: 20-30 seconds in the student's voice, one real question,
/// two glanceable talking points, and where every line came from.
class PitchCard extends ConsumerStatefulWidget {
  final String boothId;
  final Json data;
  final Future<void> Function() reload;
  const PitchCard({super.key, required this.boothId, required this.data, required this.reload});
  @override
  ConsumerState<PitchCard> createState() => _PitchCardState();
}

class _PitchCardState extends ConsumerState<PitchCard> {
  String? jobId;
  String? error;

  @override
  void didUpdateWidget(covariant PitchCard old) {
    super.didUpdateWidget(old);
    final j = widget.data['pitch_job'] as Json?;
    if (jobId == null && j != null) jobId = j['id'] as String;
  }

  @override
  void initState() {
    super.initState();
    final j = widget.data['pitch_job'] as Json?;
    if (j != null) {
      jobId = j['id'] as String;
    } else if (widget.data['pitch'] == null) {
      _run('default');
    }
  }

  Future<void> _run(String variant) async {
    setState(() => error = null);
    try {
      final r = await ref.read(apiProvider).post('/api/booths/${widget.boothId}/pitch', {'variant': variant});
      setState(() => jobId = r['job_id'] as String);
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _edit(Json p) async {
    final pc = TextEditingController(text: p['pitch'] as String? ?? '');
    final qc = TextEditingController(text: p['question'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit your pitch'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: pc, minLines: 5, maxLines: 10, decoration: const InputDecoration(labelText: 'Pitch')),
            const SizedBox(height: T.s3),
            TextField(controller: qc, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Your question')),
            const SizedBox(height: T.s2),
            const Text('Your edits teach your Voice Profile, so future pitches start closer to how you talk.',
                style: TextStyle(color: T.muted, fontSize: T.small)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await ref.read(apiProvider).put('/api/booths/${widget.boothId}/pitch', {'pitch': pc.text, 'question': qc.text});
      final lint = r['lint'] as Json;
      if (mounted) {
        toast(context, lint['ok'] == true ? 'Saved.' : 'Saved. Heads up: ${(lint['issues'] as List).join('; ')}');
      }
      await widget.reload();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.data['pitch'] as Json?;
    final resumeLabel = (p?['resume_label'] ?? widget.data['resume_label']) as String?;
    final roles = ((widget.data['booth'] as Json)['roles'] as List?)?.length ?? 0;
    final hasVoice = (widget.data['_me'] as Json?)?['has_voice'] == true;
    final source = 'From your ${resumeLabel ?? ''} resume + $roles open roles${hasVoice ? ' + your Voice Profile' : ''}';

    if (jobId != null) {
      return ResultCard(
        title: S.pitchBrief,
        source: source,
        child: JobProgress(
          jobId: jobId!,
          onDone: (_) async {
            setState(() => jobId = null);
            await widget.reload();
          },
          onError: (m) => setState(() {
            jobId = null;
            error = m;
          }),
        ),
      );
    }
    if (p == null) {
      return ResultCard(
        title: S.pitchBrief,
        source: source,
        child: error != null
            ? Banner2(text: error!, color: T.danger, bg: T.dangerBg)
            : const Text('Preparing your pitch.', style: TextStyle(color: T.muted)),
        actions: [OutlinedButton(onPressed: () => _run('default'), child: const Text('Write my pitch'))],
      );
    }
    final lint = p['lint'] as Json?;
    final critic = p['critic'] as Json?;
    final trace = ((p['trace'] as List?) ?? []).cast<Json>();
    final srcLabel = switch (p['source']) {
      'live' => 'Written now by the local model, reviewed by a separate critic pass${(p['rewrites'] ?? 0) > 0 ? ' (${p['rewrites']} rewrite${p['rewrites'] == 1 ? '' : 's'})' : ''}.',
      'cache' => 'Precomputed for Demo Mode by the same pipeline.',
      'edited' => 'Your edit.',
      'offline' => 'Offline draft built only from your resume lines. Live AI is off.',
      _ => '',
    };
    return ResultCard(
      title: S.pitchBrief,
      source: '$source · ${p['project'] != null ? 'Lead project: ${p['project']}' : ''}',
      notice: p['notice'] as String?,
      actions: [
        OutlinedButton(onPressed: () => _run('more_like_me'), child: const Text(S.moreLikeMe)),
        OutlinedButton(onPressed: () => _run('shorter'), child: const Text(S.shorter)),
        OutlinedButton(onPressed: () => _run('different_project'), child: const Text(S.differentProject)),
        TextButton.icon(onPressed: () => _edit(p), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text(S.edit)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p['pitch'] as String? ?? '', style: const TextStyle(fontSize: 18, height: 1.5)),
        const SizedBox(height: T.s2),
        Text('${_words(p['pitch'] as String? ?? '')} words · about ${(_words(p['pitch'] as String? ?? '') / 2.6).round()} seconds spoken',
            style: const TextStyle(fontSize: T.tiny, color: T.muted)),
        const SizedBox(height: T.s4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(T.s3),
          decoration: BoxDecoration(color: T.accent.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(T.radius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(S.askThis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: T.small)),
            const SizedBox(height: T.s1),
            Text(p['question'] as String? ?? '', style: const TextStyle(fontSize: T.body)),
          ]),
        ),
        const SizedBox(height: T.s3),
        const Text(S.glance, style: TextStyle(fontWeight: FontWeight.w700, fontSize: T.small, color: T.muted)),
        for (final tp in ((p['talking_points'] as List?) ?? []))
          Padding(
            padding: const EdgeInsets.only(top: T.s1),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900)),
              Expanded(child: Text('$tp')),
            ]),
          ),
        const SizedBox(height: T.s3),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              lint?['ok'] == true ? 'Checked: no banned phrases, no company praise, numbers traced' : 'Review notes',
              style: TextStyle(fontSize: T.small, color: lint?['ok'] == true ? T.success : T.warning, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(srcLabel, style: const TextStyle(fontSize: T.tiny)),
            children: [
              if (critic != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: T.s2),
                  child: Text(
                      'Critic scores: specificity ${critic['specificity']}/5 · sounds like you ${critic['sounds_like_them']}/5 · believability ${critic['believability']}/5',
                      style: const TextStyle(fontSize: T.small)),
                ),
              if (lint != null && lint['ok'] != true)
                for (final i in (lint['issues'] as List)) Text('• $i', style: const TextStyle(fontSize: T.small, color: T.warning)),
              for (final t in trace)
                Padding(
                  padding: const EdgeInsets.only(bottom: T.s2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(t['traceable'] == false ? Icons.help_outline : Icons.link, size: 16, color: t['traceable'] == false ? T.warning : T.muted),
                    const SizedBox(width: T.s2),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '"${t['sentence']}"  ', style: const TextStyle(fontSize: T.small)),
                        TextSpan(text: '← ${t['source']}', style: const TextStyle(fontSize: T.tiny, color: T.muted, fontWeight: FontWeight.w600)),
                      ])),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  static int _words(String s) => s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;
}
