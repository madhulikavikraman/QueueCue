import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';

class OrganizerPage extends ConsumerStatefulWidget {
  final String? keyParam;
  const OrganizerPage({super.key, this.keyParam});
  @override
  ConsumerState<OrganizerPage> createState() => _OrganizerPageState();
}

class _OrganizerPageState extends ConsumerState<OrganizerPage> {
  String? key;
  bool ready = false;
  int tab = 0;

  Api get api => ref.read(apiProvider);
  String get q => 'org=${Uri.encodeComponent(key ?? '')}';

  @override
  void initState() {
    super.initState();
    () async {
      var k = widget.keyParam;
      if (k != null && k.isNotEmpty) {
        await Prefs.set('qq_org_key', k);
      } else {
        k = await Prefs.get('qq_org_key');
      }
      setState(() {
        key = k;
        ready = true;
      });
    }();
  }

  Future<void> _post(String path, [Object? body]) async {
    try {
      final r = await api.post('$path?$q', body);
      if (mounted && r['message'] != null) toast(context, r['message'] as String);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: LoadingState());
    if (key == null || key!.isEmpty) {
      final c = TextEditingController();
      return Scaffold(
        appBar: AppBar(leading: const BackOrHome(), title: const Text('Organizer')),
        body: PageBody(maxWidth: 420, children: [
          TextField(controller: c, decoration: const InputDecoration(labelText: 'Organizer key')),
          const SizedBox(height: T.s3),
          FilledButton(
              onPressed: () async {
                await Prefs.set('qq_org_key', c.text.trim());
                setState(() => key = c.text.trim());
              },
              child: const Text('Open')),
        ]),
      );
    }
    return LiveBuilder(
      fetch: (api) => api.get('/api/organizer?$q'),
      listen: (t) => t == 'organizer' || t == 'fair' || t.startsWith('booth:'),
      fallbackPoll: const Duration(seconds: 8),
      builder: (context, o, reload) {
        final f = o['fair'] as Json;
        final closed = f['status'] == 'closed';
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(leading: const BackOrHome(), 
              title: Text('${f['name']} · ${closed ? 'closed' : 'open'}'),
              bottom: const TabBar(isScrollable: true, tabs: [
                Tab(text: 'Floor'),
                Tab(text: 'Fairness audit'),
                Tab(text: 'Help requests'),
                Tab(text: 'Recruiter links'),
              ]),
            ),
            body: TabBarView(children: [
              _floor(context, o, reload),
              _AuditTab(q: q),
              _help(context, o),
              _links(context, o),
            ]),
          ),
        );
      },
    );
  }

  Widget _floor(BuildContext context, Json o, Future<void> Function() reload) {
    final f = o['fair'] as Json;
    final booths = ((o['booths'] as List?) ?? []).cast<Json>();
    final stats = o['stats'] as Json;
    final closed = f['status'] == 'closed';
    final w = (f['floor_w'] as num).toInt(), h = (f['floor_h'] as num).toInt();
    return ListView(padding: const EdgeInsets.all(T.gutter), children: [
      Wrap(spacing: T.s4, runSpacing: T.s2, children: [
        _Stat('${stats['checked_in']}', 'checked in'),
        _Stat('${stats['in_lines']}', 'in lines'),
        _Stat('${stats['conversations']}', 'conversations'),
        _Stat('${stats['drops']}', 'drops'),
        _Stat('${stats['fair_play']}', 'Fair Play'),
        _Stat('${stats['line_credit']}', 'line credit'),
      ]),
      const SizedBox(height: T.s4),
      LayoutBuilder(builder: (context, cons) {
        final cell = (cons.maxWidth / (w + 1)).clamp(20.0, 100.0);
        return Container(
          decoration: BoxDecoration(color: T.surface, border: Border.all(color: T.line, width: 2), borderRadius: BorderRadius.circular(T.radius)),
          width: cell * (w + 1),
          height: cell * (h + 1.2),
          child: Stack(children: [
            Positioned(left: 0, right: 0, bottom: 4, child: Text('ENTRANCE', textAlign: TextAlign.center, style: TextStyle(fontSize: T.tiny, color: T.muted, letterSpacing: 4))),
            for (final b in booths)
              Positioned(
                left: (b['x'] as num) * cell,
                top: (b['y'] as num) * cell - cell * 0.6,
                width: cell * 2,
                height: cell * 1.6,
                child: Tooltip(
                  message: '${b['name']}: ${b['line']} in line, ${(b['estimate'] as Json)['label']}',
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: b['status'] == 'open' ? T.heatFor((b['line'] as num).toInt()) : T.muted,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: T.ink, width: 1.5),
                    ),
                    child: FittedBox(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('${b['number']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        Text('${b['name']}'.split(' ').first, style: const TextStyle(color: Colors.white, fontSize: 11)),
                        Text('${b['line']} · ${(b['estimate'] as Json)['label']}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        );
      }),
      const SizedBox(height: T.s2),
      Row(children: [
        for (final (i, lbl) in ['0-2', '3-5', '6-8', '9-12', '13+'].indexed) ...[
          Container(width: 14, height: 14, color: T.heat[i]),
          const SizedBox(width: 4),
          Text(lbl, style: const TextStyle(fontSize: T.tiny)),
          const SizedBox(width: T.s3),
        ],
        const Text('people in line', style: TextStyle(fontSize: T.tiny, color: T.muted)),
      ]),
      const SizedBox(height: T.s5),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Committed lottery seed (SHA-256)', style: TextStyle(fontWeight: FontWeight.w700)),
            SelectableText('${f['seed_hash']}', style: const TextStyle(fontFamily: 'monospace', fontSize: T.small)),
            if (f['seed'] != null) ...[
              const SizedBox(height: T.s2),
              const Text('Revealed seed', style: TextStyle(fontWeight: FontWeight.w700)),
              SelectableText('${f['seed']}', style: const TextStyle(fontFamily: 'monospace', fontSize: T.small)),
              const Text('Check: sha256(seed) equals the hash above. Tie-break = sha256(seed:booth:student), ascending.', style: TextStyle(fontSize: T.tiny, color: T.muted)),
            ] else
              const Text('Revealed when the fair closes so anyone can re-run the tie-breaks.', style: TextStyle(fontSize: T.tiny, color: T.muted)),
          ]),
        ),
      ),
      const SizedBox(height: T.s3),
      _Settings(f: f, q: q, aiLive: o['ai_live'] == true),
      const SizedBox(height: T.s3),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Demo Mode', style: TextStyle(fontWeight: FontWeight.w700)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulate crowd'),
              subtitle: const Text('Simulated students join lines and get served every few seconds. Real students are never moved.'),
              value: o['simulating'] == true,
              onChanged: (v) => _post('/api/organizer/simulate', {'on': v}),
            ),
            OutlinedButton.icon(
              onPressed: () => _post('/api/organizer/refresh-times'),
              icon: const Icon(Icons.update),
              label: const Text('Refresh demo times'),
            ),
            const Text('Moves the seeded demo data to "now" (waits, lines, timestamps). Real sign-ups are not touched.',
                style: TextStyle(fontSize: T.tiny, color: T.muted)),
          ]),
        ),
      ),
      const SizedBox(height: T.s3),
      Card(
        color: T.dangerBg,
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Danger zone', style: TextStyle(fontWeight: FontWeight.w800, color: T.danger)),
            const Text('Reset deletes EVERY account, line, card swap and point, including real sign-ups, and restores the seed data.',
                style: TextStyle(fontSize: T.small)),
            const SizedBox(height: T.s2),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: T.danger, side: const BorderSide(color: T.danger, width: 1.5)),
              onPressed: () async {
                final c = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Reset all data?'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Type RESET to confirm. This cannot be undone.'),
                      const SizedBox(height: T.s3),
                      TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'RESET')),
                    ]),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: T.danger),
                        onPressed: () => Navigator.pop(d, c.text.trim() == 'RESET'),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await _post('/api/organizer/reset');
                } else if (ok == false && c.text.isNotEmpty && context.mounted) {
                  toast(context, 'Not reset: you need to type RESET exactly.');
                }
              },
              child: const Text('Reset demo data'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: T.s5),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: closed ? T.muted : T.brand),
        onPressed: closed
            ? null
            : () async {
                final ok = await _confirmDialog(context, 'Close the fair?',
                    'Everyone still in a line gets line credit. Every checked-in student\'s best resume goes to their top 3 fit recruiters. The lottery seed is revealed.');
                if (ok) await _post('/api/organizer/close');
              },
        child: Text(closed ? 'Fair closed' : 'Close fair'),
      ),
    ]);
  }

  Widget _help(BuildContext context, Json o) {
    final reqs = ((o['access_requests'] as List?) ?? []).cast<Json>();
    final booths = ((o['booths'] as List?) ?? []).cast<Json>();
    return ListView(padding: const EdgeInsets.all(T.gutter), children: [
      const Text('Accessibility requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: T.h2)),
      const Text('Staff can confirm a conversation held at the accessibility desk or by video, so these students are never pushed into a lower section.',
          style: TextStyle(color: T.muted, fontSize: T.small)),
      const SizedBox(height: T.s3),
      if (reqs.isEmpty) const EmptyState(icon: Icons.accessibility_new, title: 'No requests'),
      const SizedBox(height: T.s5),
      const Text('Forgot password', style: TextStyle(fontWeight: FontWeight.w800, fontSize: T.h2)),
      const Text('Sets a temporary password for a student or recruiter. Tell them in person; they can change it later.',
          style: TextStyle(color: T.muted, fontSize: T.small)),
      const SizedBox(height: T.s2),
      _ResetPassword(onReset: (email) async {
        try {
          final r = await api.post('/api/organizer/reset-password?$q', {'email': email});
          if (!context.mounted) return;
          await showDialog(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Temporary password'),
              content: SelectableText(r['message'] as String, style: const TextStyle(fontSize: T.h3)),
              actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Done'))],
            ),
          );
        } on ApiException catch (e) {
          if (context.mounted) toast(context, e.message);
        }
      }),
      for (final r in reqs)
        Card(
          child: ListTile(
            leading: PixelAvatar(r['avatar'] as String, size: 36),
            title: Text('${r['name']}: ${r['need']}'),
            subtitle: Text('${r['booth_name'] != null ? 'At Booth ${r['booth_number']} (${r['booth_name']})' : 'Help desk'} · ${hhmm(r['created_at'])} · ${r['status']}'),
            trailing: Wrap(spacing: T.s2, children: [
              OutlinedButton(
                onPressed: () async {
                  final bid = await showDialog<String>(
                    context: context,
                    builder: (c) => SimpleDialog(title: const Text('Confirm a conversation with which booth?'), children: [
                      for (final b in booths) SimpleDialogOption(onPressed: () => Navigator.pop(c, b['id'] as String), child: Text('${b['number']}. ${b['name']}')),
                    ]),
                  );
                  if (bid != null) await _post('/api/organizer/staff-confirm', {'booth_id': bid, 'student_id': r['student_id']});
                },
                child: const Text('Staff confirm'),
              ),
              if (r['status'] == 'open') TextButton(onPressed: () => _post('/api/organizer/access/${r['id']}/resolve'), child: const Text('Resolved')),
            ]),
          ),
        ),
    ]);
  }

  Widget _links(BuildContext context, Json o) {
    final booths = ((o['booths'] as List?) ?? []).cast<Json>();
    final origin = apiBase();
    return ListView(padding: const EdgeInsets.all(T.gutter), children: [
      const Text('Send each recruiter their booth link. Students join lines with a button in the app; cards swap when the recruiter accepts.',
          style: TextStyle(color: T.muted)),
      const SizedBox(height: T.s3),
      Wrap(spacing: T.s3, runSpacing: T.s3, children: [
        for (final b in booths)
          SizedBox(
            width: 260,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(T.s3),
                child: Column(children: [
                  Text('Booth ${b['number']}', style: const TextStyle(fontSize: T.tiny, color: T.muted)),
                  Text('${b['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: T.s2),
                  Text('${b['line']} in line · ${(b['estimate'] as Json)['label']}', style: const TextStyle(fontSize: T.small)),
                  const Divider(),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: '$origin/booth/${b['id']}?key=${b['booth_key']}'));
                      if (context.mounted) toast(context, 'Recruiter link copied.');
                    },
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Copy recruiter link'),
                  ),
                  TextButton(onPressed: () => api.openUrl('/booth/${b['id']}?key=${b['booth_key']}'), child: const Text('Open booth view')),
                ]),
              ),
            ),
          ),
      ]),
    ]);
  }

  Future<bool> _confirmDialog(BuildContext context, String title, String body) async =>
      (await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(title: Text(title), content: Text(body), actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
        ]),
      )) ==
      true;
}

class _Stat extends StatelessWidget {
  final String v;
  final String label;
  const _Stat(this.v, this.label);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(fontSize: T.tiny, color: T.muted)),
      ]);
}

class _Settings extends ConsumerStatefulWidget {
  final Json f;
  final String q;
  final bool aiLive;
  const _Settings({required this.f, required this.q, required this.aiLive});
  @override
  ConsumerState<_Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<_Settings> {
  late double wFit = (widget.f['w_fit'] as num).toDouble();
  late int cap = (widget.f['effort_cap_min'] as num).toInt();
  Json? health;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).get('/api/health').then((h) {
      if (mounted) setState(() => health = h);
    });
  }

  Future<void> _save(Map<String, Object?> body) async {
    try {
      await ref.read(apiProvider).post('/api/organizer/settings?${widget.q}', body);
      final h = await ref.read(apiProvider).get('/api/health');
      if (mounted) setState(() => health = h);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Fairness settings (shown on every recruiter screen)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: T.s2),
            Text('Score = ${wFit.toStringAsFixed(2)} x Fit + ${(1 - wFit).toStringAsFixed(2)} x Effort'),
            Slider(value: wFit, min: 0.6, max: 1.0, divisions: 40, label: wFit.toStringAsFixed(2), onChanged: (v) => setState(() => wFit = v), onChangeEnd: (v) => _save({'w_fit': double.parse(v.toStringAsFixed(2))})),
            Text('Effort cap: $cap minutes of waiting'),
            Slider(value: cap.toDouble(), min: 15, max: 120, divisions: 21, label: '$cap', onChanged: (v) => setState(() => cap = v.round()), onChangeEnd: (v) => _save({'cap_min': v.round()})),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Live AI (local model)'),
              subtitle: Text(health == null
                  ? 'Checking the host laptop'
                  : 'Model ${health!['model']}: ${health!['ollama_up'] == true ? (health!['model_pulled'] == true ? 'ready' : 'Ollama up, model not pulled') : 'Ollama not running'}. '
                      'Speech-to-text: ${health!['whisper'] == true ? 'ready' : 'not set up'}. Off = Demo Mode cache.'),
              value: widget.aiLive,
              onChanged: (v) => _save({'ai_live': v}),
            ),
          ]),
        ),
      );
}

class _AuditTab extends ConsumerWidget {
  final String q;
  const _AuditTab({required this.q});
  @override
  Widget build(BuildContext context, WidgetRef ref) => LiveBuilder(
        fetch: (api) => api.get('/api/organizer/audit?$q'),
        listen: (t) => t == 'fair',
        fallbackPoll: const Duration(seconds: 30),
        builder: (context, a, reload) {
          final hours = ((a['avg_rank_by_hour'] as List?) ?? []).cast<Json>();
          Widget groups(String title, Json g) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(T.s4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Text('Flag = below 80% of the best group\'s rate (four-fifths rule of thumb).', style: TextStyle(fontSize: T.tiny, color: T.muted)),
                    const SizedBox(height: T.s2),
                    for (final r in ((g['groups'] as List?) ?? []).cast<Json>())
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          SizedBox(width: 200, child: Text('${r['group']}', style: const TextStyle(fontSize: T.small))),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: (r['rate'] as num).toDouble().clamp(0, 1),
                              minHeight: 10,
                              color: r['flag'] == true ? T.danger : T.success,
                              backgroundColor: T.surfaceAlt,
                            ),
                          ),
                          const SizedBox(width: T.s2),
                          SizedBox(
                            width: 120,
                            child: Text('${((r['rate'] as num) * 100).round()}% · n=${r['students']}${r['flag'] == true ? ' · FLAG' : ''}',
                                style: TextStyle(fontSize: T.tiny, color: r['flag'] == true ? T.danger : T.ink, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                  ]),
                ),
              );
          final corr = (a['arrival_rank_correlation'] as num).toDouble();
          return ListView(padding: const EdgeInsets.all(T.gutter), children: [
            Row(children: [
              Expanded(child: Text('Post-fair audit${a['fair_status'] == 'open' ? ' (live, fair still open)' : ''}', style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w800))),
              OutlinedButton.icon(
                onPressed: () => ref.read(apiProvider).openUrl('/api/organizer/audit.csv?$q'),
                icon: const Icon(Icons.download),
                label: const Text('Export CSV'),
              ),
            ]),
            const SizedBox(height: T.s3),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(T.s4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Arrival time vs. shortlist rank (within section)', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(corr.toStringAsFixed(3), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: corr.abs() < 0.2 ? T.success : T.warning)),
                  Text('${a['correlation_note']} (${a['n_points']} placements)', style: const TextStyle(fontSize: T.small)),
                  const SizedBox(height: T.s2),
                  Text('Across sections: ${a['overall_correlation']}. ${a['overall_note']}', style: const TextStyle(fontSize: T.tiny, color: T.muted)),
                ]),
              ),
            ),
            const SizedBox(height: T.s3),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(T.s4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Average rank by arrival hour (0 = top of list, 1 = bottom)', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: T.s2),
                  for (final h in hours)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(width: 60, child: Text('${h['label']}', style: const TextStyle(fontSize: T.small))),
                        Expanded(child: LinearProgressIndicator(value: (h['avg_rank_pct'] as num).toDouble(), minHeight: 10, backgroundColor: T.surfaceAlt)),
                        SizedBox(width: 90, child: Text('  ${(h['avg_rank_pct'] as num).toStringAsFixed(2)} · n=${h['n']}', style: const TextStyle(fontSize: T.tiny))),
                      ]),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: T.s3),
            groups('Fair Play delivery by major', a['fair_play_by_major'] as Json),
            const SizedBox(height: T.s3),
            groups('Fair Play delivery by work authorization', a['fair_play_by_work_auth'] as Json),
            const SizedBox(height: T.s2),
            Text('${a['rate_meaning']}', style: const TextStyle(fontSize: T.tiny, color: T.muted)),
            const SizedBox(height: T.s3),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(T.s4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Lottery seed', style: TextStyle(fontWeight: FontWeight.w700)),
                  SelectableText('hash: ${a['seed_hash']}', style: const TextStyle(fontFamily: 'monospace', fontSize: T.tiny)),
                  SelectableText('seed: ${a['seed'] ?? '(revealed at close)'}', style: const TextStyle(fontFamily: 'monospace', fontSize: T.tiny)),
                  Text('${a['seed_note']}', style: const TextStyle(fontSize: T.tiny, color: T.muted)),
                ]),
              ),
            ),
          ]);
        },
      );
}

class _ResetPassword extends StatefulWidget {
  final Future<void> Function(String email) onReset;
  const _ResetPassword({required this.onReset});
  @override
  State<_ResetPassword> createState() => _ResetPasswordState();
}

class _ResetPasswordState extends State<_ResetPassword> {
  final email = TextEditingController();
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'their email'))),
        const SizedBox(width: T.s2),
        FilledButton(onPressed: () => widget.onReset(email.text.trim()), child: const Text('Reset password')),
      ]);
}
