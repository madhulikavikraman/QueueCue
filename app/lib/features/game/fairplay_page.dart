import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';

class FairPlayPage extends ConsumerWidget {
  const FairPlayPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(leading: const BackOrHome(), title: const Text(S.fairPlay)),
        body: LiveBuilder(
          fetch: (api) => api.get('/api/me/fairplay'),
          listen: (t) => t.startsWith('student:') || t == 'fair',
          builder: (context, d, reload) {
            final targets = ((d['targets'] as List?) ?? []).cast<Json>();
            final closed = d['fair_closed'] == true;
            return PageBody(onRefresh: reload, children: [
              Banner2(text: d['message'] as String, icon: Icons.verified_outlined, color: closed ? T.success : T.info, bg: closed ? T.successBg : T.infoBg),
              const SizedBox(height: T.s3),
              const Text(
                'Chosen by fit among companies that can hire you (major and work authorization). Not by points, and not by how long you stayed.',
                style: TextStyle(color: T.muted, fontSize: T.small),
              ),
              const SizedBox(height: T.s3),
              if (targets.isEmpty) const EmptyState(icon: Icons.hourglass_empty, title: 'Your fit scores are still being computed'),
              for (final t in targets)
                Card(
                  child: CheckboxListTile(
                    value: t['excluded'] != true,
                    onChanged: closed
                        ? null
                        : (v) async {
                            try {
                              await ref.read(apiProvider).post('/api/me/fairplay/${t['booth_id']}', {'excluded': v != true});
                              await reload();
                            } on ApiException catch (e) {
                              if (context.mounted) toast(context, e.message);
                            }
                          },
                    title: Text('${t['name']} · fit ${t['fit_pct']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      '${t['resume_label']} resume',
                      if (t['already_reached'] == true)
                        'already reached via ${t['reached_via'] == 'conversation' ? 'your conversation' : t['reached_via'] == 'fairplay' ? 'Fair Play' : t['reached_via'] == 'line_credit' ? 'line credit' : 'your drop'}',
                      if (t['excluded'] == true) 'will not be sent',
                    ].join(' · ')),
                  ),
                ),
            ]);
          },
        ),
      );
}
