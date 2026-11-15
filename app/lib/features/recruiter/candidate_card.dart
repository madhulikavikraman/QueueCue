import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import 'quick_rate.dart';

/// One student on the recruiter's list: avatar, name, pile, memory note, time
/// met and blind Fit, so the recruiter can recall someone among hundreds.
class CandidateCard extends ConsumerStatefulWidget {
  final Json c;
  final List<String> piles;
  final bool blind;
  final String boothId;
  final String keyQuery;
  final Widget? handle;
  const CandidateCard(
      {super.key, required this.c, required this.piles, required this.blind, required this.boothId, required this.keyQuery, this.handle});
  @override
  ConsumerState<CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends ConsumerState<CandidateCard> {
  bool revealed = false;
  late final noteC = TextEditingController(text: widget.c['private_note'] as String? ?? '');

  Json get c => widget.c;
  Json get s => c['student'] as Json;
  bool get hide => widget.blind && !revealed;
  Api get api => ref.read(apiProvider);

  Future<void> _mark(Map<String, Object?> body) async {
    try {
      await api.post('/api/recruiter/${widget.boothId}/mark/${s['id']}?${widget.keyQuery}', body);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _viewResume() async {
    try {
      final r = await api.get('/api/recruiter/${widget.boothId}/resume/${s['id']}?${widget.keyQuery}&rid=${c['resume_id']}${hide ? '&blind=1' : ''}');
      if (!mounted) return;
      final sum = r['summary'] as Json?;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${hide ? 'Candidate' : s['name']} · ${r['label']} resume${r['blind'] == true ? ' (blind)' : ''}'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (sum != null) ...[
                  Text(sum['headline'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                  for (final h in (sum['highlights'] as List? ?? [])) Text('• $h', style: const TextStyle(fontSize: T.small)),
                  const Divider(height: T.s5),
                ],
                SelectableText(r['text'] as String? ?? '', style: const TextStyle(fontSize: T.small, height: 1.45)),
              ]),
            ),
          ),
          actions: [
            if (c['has_pdf'] == true && !hide)
              TextButton(
                  onPressed: () => api.openUrl('/api/recruiter/${widget.boothId}/resume/${s['id']}/pdf?${widget.keyQuery}&rid=${c['resume_id']}'),
                  child: const Text('Open PDF')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kinds = ((c['kinds'] as List?) ?? []).cast<String>();
    final sum = c['summary'] as Json?;
    final stars = (c['stars'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(T.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.handle != null) Padding(padding: const EdgeInsets.only(right: T.s2, top: T.s2), child: widget.handle!),
            Text('${c['section_rank']}', style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w900, color: T.muted)),
            const SizedBox(width: T.s3),
            PixelAvatar(s['avatar'] as String, size: 44, hidden: hide),
            const SizedBox(width: T.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hide ? 'Candidate ${c['rank']}' : s['name'] as String, style: const TextStyle(fontSize: T.h3, fontWeight: FontWeight.w800)),
                Text('${s['degree'] ?? ''} ${s['major']}', style: const TextStyle(fontSize: T.small, color: T.muted)),
                const SizedBox(height: T.s1),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (kinds.contains('met')) Pill('Met ${hhmm(c['met_at'])} (${c['met_method']})', fg: T.success, bg: T.successBg, icon: Icons.handshake_outlined),
                  if (c['line_credit_label'] != null) Pill(c['line_credit_label'] as String, fg: T.warning, bg: T.warningBg, icon: Icons.hourglass_bottom),
                  if (kinds.contains('drop')) const Pill('Dropped resume', icon: Icons.send_outlined),
                  if (kinds.contains('fairplay')) const Pill('Fair Play match', fg: T.info, bg: T.infoBg, icon: Icons.verified_outlined),
                  if (c['resume_label'] != null) Pill('${c['resume_label']} resume'),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              FitChip(c['fit'] as num?),
              const SizedBox(height: 4),
              Text('effort ${c['effort']} · score ${c['score']}', style: const TextStyle(fontSize: 11, color: T.muted)),
            ]),
          ]),
          if (c['reason'] != null) ...[
            const SizedBox(height: T.s2),
            Text('Why this rank: ${c['reason']}', style: const TextStyle(fontSize: T.small)),
          ],
          if (sum != null) ...[
            const SizedBox(height: T.s2),
            Text(sum['headline'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: T.small)),
            for (final h in ((sum['highlights'] as List?) ?? []).take(3)) Text('• $h', style: const TextStyle(fontSize: T.small)),
          ],
          if (c['note'] != null && !hide) ...[
            const SizedBox(height: T.s2),
            Container(
              padding: const EdgeInsets.all(T.s2),
              color: T.surfaceAlt,
              child: Text('Note from student: ${c['note']}', style: const TextStyle(fontSize: T.small)),
            ),
          ],
          if (((c['tags'] as List?) ?? const []).isNotEmpty && !hide) ...[
            const SizedBox(height: T.s2),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final t in (c['tags'] as List)) Pill('$t', fg: T.onAccent, bg: T.accent, icon: Icons.check),
            ]),
          ],
          if (c['memory_note'] != null && !hide) ...[
            const SizedBox(height: T.s2),
            Text('Your memory note: ${c['memory_note']}', style: const TextStyle(fontSize: T.small, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: T.s2),
          Text('Arrived ${hhmm(c['arrival_at'])} (information only) · waited ${c['waited_min']} min',
              style: const TextStyle(fontSize: T.tiny, color: T.muted)),
          const Divider(height: T.s4),
          Wrap(spacing: T.s2, runSpacing: T.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (!hide)
              DropdownButton<String?>(
                value: widget.piles.contains(c['pile']) ? c['pile'] as String? : null,
                hint: const Text('Pile'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No pile')),
                  for (final p in widget.piles) DropdownMenuItem<String?>(value: p, child: Text(p)),
                ],
                onChanged: (v) => _mark(v == null ? {'clear_pile': true} : {'pile': v}),
              ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '$i star${i == 1 ? '' : 's'} (private)',
                  onPressed: () => _mark(i == stars ? {'clear_stars': true} : {'stars': i}),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= stars ? T.accent : T.muted),
                ),
            ]),
            if (!hide)
              FilledButton.tonalIcon(
                onPressed: () => showQuickRate(context, ref,
                    boothId: widget.boothId, keyQuery: widget.keyQuery, student: s, piles: widget.piles, current: c),
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Quick rate'),
              ),
            TextButton.icon(onPressed: _viewResume, icon: const Icon(Icons.description_outlined, size: 18), label: const Text('Resume')),
            if (widget.blind)
              TextButton(onPressed: () => setState(() => revealed = !revealed), child: Text(revealed ? 'Hide' : 'Reveal')),
          ]),
          if (!hide)
            TextField(
              controller: noteC,
              decoration: const InputDecoration(isDense: true, hintText: 'Private note (only you see this)'),
              onSubmitted: (v) => _mark({'private_note': v}),
              onTapOutside: (_) {
                if (noteC.text != (c['private_note'] ?? '')) _mark({'private_note': noteC.text});
              },
            ),
        ]),
      ),
    );
  }
}
