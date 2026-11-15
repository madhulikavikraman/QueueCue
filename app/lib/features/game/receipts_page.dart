import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';

/// Fairness receipt: for every recruiter list I am on, my Fit, Effort, Score
/// and the formula. Never shows other students.
class ReceiptsPage extends ConsumerWidget {
  const ReceiptsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(leading: const BackOrHome(), title: const Text(S.whyHere)),
        body: LiveBuilder(
          fetch: (api) => api.get('/api/me/receipts'),
          listen: (t) => t.startsWith('student:') || t.startsWith('booth:'),
          builder: (context, d, reload) {
            final items = ((d['items'] as List?) ?? []).cast<Json>();
            return PageBody(onRefresh: reload, children: [
              if (items.isEmpty)
                const EmptyState(icon: Icons.inbox_outlined, title: 'You are not on any recruiter list yet', body: 'Drop a resume, wait in a line, or meet a recruiter.'),
              for (final r in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: T.s3),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(T.s4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((r['booth'] as Json)['name'] as String, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: T.s1),
                        Text('Section: ${r['section_label']} · #${r['section_rank']} of ${r['section_size']} in that section',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: T.s3),
                        Row(children: [
                          _Num('Fit', '${r['fit']}'),
                          _Num('Waited', '${r['waited_min']} min'),
                          _Num('Effort', '${r['effort']}'),
                          _Num('Score', '${r['score']}'),
                        ]),
                        const SizedBox(height: T.s3),
                        Text(r['worked'] as String, style: const TextStyle(fontFamily: 'monospace', fontSize: T.small)),
                        const SizedBox(height: T.s2),
                        Text(r['formula'] as String, style: const TextStyle(fontSize: T.small, color: T.muted)),
                        const SizedBox(height: T.s2),
                        Text('Not used: ${(r['not_used'] as List).join(', ')}.', style: const TextStyle(fontSize: T.small, color: T.muted)),
                      ]),
                    ),
                  ),
                ),
            ]);
          },
        ),
      );
}

class _Num extends StatelessWidget {
  final String label;
  final String v;
  const _Num(this.label, this.v);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(fontSize: T.tiny, color: T.muted)),
        ]),
      );
}
