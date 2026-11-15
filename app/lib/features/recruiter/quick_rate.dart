import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';

/// "They did this": one-tap evidence tags. Behavior-based, never identity.
const quickTags = [
  'Strong project',
  'Great questions',
  'Clear communicator',
  'Researched us',
  'Role fit',
  'Follow up',
  'Referral',
];

/// Quick rate sheet: stars, pile, tags, memory note. Opens right after a card
/// swap and from any candidate. Saves in one tap. Private to the recruiter.
Future<void> showQuickRate(
  BuildContext context,
  WidgetRef ref, {
  required String boothId,
  required String keyQuery,
  required Json student,
  required List<String> piles,
  String? headline,
  Json? current,
}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _QuickRate(
          boothId: boothId,
          keyQuery: keyQuery,
          student: student,
          piles: piles,
          headline: headline,
          current: current,
        ),
      ),
    );

class _QuickRate extends ConsumerStatefulWidget {
  final String boothId;
  final String keyQuery;
  final Json student;
  final List<String> piles;
  final String? headline;
  final Json? current;
  const _QuickRate({required this.boothId, required this.keyQuery, required this.student, required this.piles, this.headline, this.current});
  @override
  ConsumerState<_QuickRate> createState() => _QuickRateState();
}

class _QuickRateState extends ConsumerState<_QuickRate> {
  late int stars = ((widget.current?['stars'] as num?) ?? 0).toInt();
  late String? pile = widget.current?['pile'] as String?;
  late final Set<String> tags = {...((widget.current?['tags'] as List?) ?? const []).map((e) => '$e')};
  late final memo = TextEditingController(text: widget.current?['memory_note'] as String? ?? '');
  bool saving = false;

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await ref.read(apiProvider).post('/api/recruiter/${widget.boothId}/mark/${widget.student['id']}?${widget.keyQuery}', {
        if (stars > 0) 'stars': stars,
        if (pile != null) 'pile': pile else 'clear_pile': true,
        'tags': tags.toList(),
        'memory_note': memo.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        toast(context, 'Saved for ${widget.student['name']}.');
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 0, T.gutter, T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              PixelAvatar(widget.student['avatar'] as String? ?? 'fox', size: 44),
              const SizedBox(width: T.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${widget.student['name']}', style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w800)),
                  Text(widget.headline ?? '${widget.student['degree'] ?? ''} ${widget.student['major'] ?? ''}',
                      style: const TextStyle(color: T.muted, fontSize: T.small)),
                ]),
              ),
            ]),
            const SizedBox(height: T.s4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 40,
                  tooltip: '$i star${i == 1 ? '' : 's'}',
                  onPressed: () => setState(() => stars = stars == i ? 0 : i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= stars ? T.accent : T.muted),
                ),
            ]),
            const SizedBox(height: T.s2),
            const Text('Pile', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: T.s2),
            Wrap(spacing: T.s2, runSpacing: T.s2, children: [
              for (final p in widget.piles)
                ChoiceChip(label: Text(p), selected: pile == p, onSelected: (v) => setState(() => pile = v ? p : null)),
            ]),
            const SizedBox(height: T.s4),
            const Text('They did this', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: T.s2),
            Wrap(spacing: T.s2, runSpacing: T.s2, children: [
              for (final t in quickTags)
                FilterChip(
                  label: Text(t),
                  selected: tags.contains(t),
                  onSelected: (v) => setState(() => v ? tags.add(t) : tags.remove(t)),
                ),
            ]),
            const SizedBox(height: T.s4),
            TextField(
              controller: memo,
              decoration: const InputDecoration(labelText: 'Memory note (optional)', hintText: 'robotics club, asked about sim-to-real'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: T.s2),
            const Text('Private to you. Never changes the suggested order.', style: TextStyle(fontSize: T.tiny, color: T.muted)),
            const SizedBox(height: T.s3),
            FilledButton(onPressed: saving ? null : _save, child: const Text('Save')),
          ]),
        ),
      );
}
