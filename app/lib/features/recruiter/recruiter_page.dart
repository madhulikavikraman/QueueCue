import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';
import 'candidate_card.dart';
import 'quick_rate.dart';

enum SortMode { suggested, stars, mine }

class RecruiterPage extends ConsumerStatefulWidget {
  final String boothId;
  final String? keyParam;
  /// 'both' (laptop booth link), 'line' or 'list' (recruiter app tabs).
  final String mode;
  const RecruiterPage({super.key, required this.boothId, this.keyParam, this.mode = 'both'});
  @override
  ConsumerState<RecruiterPage> createState() => _RecruiterPageState();
}

class _RecruiterPageState extends ConsumerState<RecruiterPage> {
  String? key;
  bool loadingKey = true;
  SortMode sort = SortMode.suggested;
  bool blind = false;
  Set<String> pileFilter = {};
  double minFit = 0;
  String section = '';

  Api get api => ref.read(apiProvider);
  String get q => 'key=${Uri.encodeComponent(key ?? '')}';

  @override
  void initState() {
    super.initState();
    _initKey();
  }

  Future<void> _initKey() async {
    var k = widget.keyParam;
    if (k != null && k.isNotEmpty) {
      await Prefs.set('qq_booth_key_${widget.boothId}', k);
    } else {
      k = await Prefs.get('qq_booth_key_${widget.boothId}');
    }
    setState(() {
      key = k;
      loadingKey = false;
    });
  }

  // ------------------------------------------------------------ confirm flow
  Future<void> _confirm({String? code, String? studentId, String? number, bool group = false, required Json view}) async {
    try {
      final r = await api.post('/api/recruiter/${widget.boothId}/confirm?$q', {
        if (code != null) 'code': code,
        if (studentId != null) 'student_id': studentId,
        if (number != null) 'number': number,
        'group': group,
      });
      if (!mounted) return;
      await _afterConfirm(r, view);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.data['needs_group'] == true) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text(S.groupChat),
            content: Text('${e.message}\nConfirm ${e.data['student_name'] ?? 'this student'} too?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, group chat')),
            ],
          ),
        );
        if (ok == true) await _confirm(code: code, studentId: studentId, number: number, group: true, view: view);
      } else {
        toast(context, e.message);
      }
    }
  }

  /// One optional tap to sort into a pile + a 3-second memory note.
  /// After any card swap: one quick-rate sheet (stars, pile, tags, note).
  Future<void> _afterConfirm(Json r, Json view) async {
    final st = r['student'] as Json;
    toast(context, r['message'] as String? ?? 'Cards swapped.');
    await showQuickRate(context, ref,
        boothId: widget.boothId,
        keyQuery: q,
        student: st,
        piles: (((view['booth'] as Json)['piles'] as List?) ?? []).cast<String>(),
        headline: '${st['degree'] ?? ''} ${st['major']} · waited ${r['waited_min'] ?? 0} min · cards swapped');
  }

  /// Recruiter types the number shown on the student's card.
  Future<void> _byNumber(Json view) async {
    final c = TextEditingController();
    final n = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter student number'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '#  ', hintText: 'Card number (3 or 4 digits)'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Swap cards')),
        ],
      ),
    );
    if (n != null && n.trim().isNotEmpty) await _confirm(number: n.trim(), view: view);
  }

  /// Accept a card the student sent from their phone.
  Future<void> _respond(Json req, bool accept, Json view, {bool group = false}) async {
    try {
      final r = await api.post('/api/recruiter/${widget.boothId}/requests/${req['id']}/${accept ? 'accept' : 'decline'}?$q', {'group': group});
      if (!mounted) return;
      if (accept) {
        await _afterConfirm(r, view);
      } else {
        toast(context, 'Declined.');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.data['needs_group'] == true) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text(S.groupChat),
            content: Text('${e.message}\nAccept ${(req['student'] as Json)['name']} too?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, group chat')),
            ],
          ),
        );
        if (ok == true) await _respond(req, true, view, group: true);
      } else {
        toast(context, e.message);
      }
    }
  }

  Future<void> _renamePiles(List<String> piles) async {
    final cs = [for (var i = 0; i < 6; i++) TextEditingController(text: i < piles.length ? piles[i] : '')];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Piles'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Up to 6. The first two count as "high" for the second-look check.', style: TextStyle(fontSize: T.small, color: T.muted)),
            for (var i = 0; i < 6; i++)
              Padding(padding: const EdgeInsets.only(top: T.s2), child: TextField(controller: cs[i], decoration: InputDecoration(labelText: 'Pile ${i + 1}'))),
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
      await api.post('/api/recruiter/${widget.boothId}/piles?$q', {'piles': cs.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList()});
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  int get _activeFilters => pileFilter.length + (minFit > 0 ? 1 : 0) + (section.isNotEmpty ? 1 : 0);

  String _filterQuery({bool topRated = false}) {
    final p = <String>[q];
    if (topRated) {
      p.add('min_stars=3.5');
    } else {
      if (pileFilter.isNotEmpty) p.add('pile=${Uri.encodeComponent(pileFilter.join(','))}');
      if (minFit > 0) p.add('min_fit=$minFit');
      if (section.isNotEmpty) p.add('section=$section');
    }
    return p.join('&');
  }

  @override
  Widget build(BuildContext context) {
    if (loadingKey) return const Scaffold(body: LoadingState());
    if (key == null || key!.isEmpty) {
      return Scaffold(
        appBar: AppBar(leading: widget.mode == 'both' ? const BackOrHome() : null, automaticallyImplyLeading: false, title: const Text('Booth view')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'This booth link needs a key',
          body: 'Open the link the organizer gave you, or sign in.',
          action: FilledButton(onPressed: () => context.go('/recruiter'), child: const Text(S.recruiterLogin)),
        ),
      );
    }
    return LiveBuilder(
      fetch: (api) => api.get('/api/recruiter/${widget.boothId}?$q'),
      listen: (t) => t == 'booth:${widget.boothId}' || t == 'fair',
      fallbackPoll: const Duration(seconds: 10),
      builder: (context, v, reload) {
        final b = v['booth'] as Json;
        final wide = MediaQuery.of(context).size.width >= 980;
        final linePanel = _LinePanel(
          view: v,
          onMet: (sid) => _confirm(studentId: sid, view: v),
          onNoShow: (sid, name) async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('$name is not here?'),
                content: const Text('They leave your line (no line credit). The next person moves up.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove from line')),
                ],
              ),
            );
            if (ok != true) return;
            try {
              final r = await api.post('/api/recruiter/${widget.boothId}/noshow?$q', {'student_id': sid});
              if (context.mounted) toast(context, r['message'] as String);
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message);
            }
          },
          onNumber: () => _byNumber(v),
          onRespond: (req, accept) => _respond(req, accept, v),
        );
        final list = _shortlist(context, v, reload);
        return Scaffold(
          appBar: AppBar(leading: widget.mode == 'both' ? const BackOrHome() : null, automaticallyImplyLeading: false, 
            title: Text('${b['name']} · Booth ${b['number']}'),
            actions: [
              if (b['status'] != 'open')
                TextButton(
                    onPressed: () async {
                      await api.post('/api/recruiter/${widget.boothId}/reopen?$q');
                      await reload();
                    },
                    child: const Text('Reopen line')),
              PopupMenuButton<String>(
                onSelected: (k) async {
                  switch (k) {
                    case 'close':
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Close your line?'),
                          content: const Text('Everyone still waiting moves to your inbox under "Waited for you", with how long they waited.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close line')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        final r = await api.post('/api/recruiter/${widget.boothId}/close?$q');
                        if (context.mounted) toast(context, r['message'] as String);
                      }
                    case 'piles':
                      await _renamePiles((((b['piles'] as List?) ?? []).cast<String>()));
                    case 'top':
                      await api.openUrl('/api/recruiter/${widget.boothId}/export.zip?${_filterQuery(topRated: true)}');
                  }
                },
                itemBuilder: (c) => [
                  const PopupMenuItem(value: 'top', child: Text('Download top rated (over 3.5 stars)')),
                  const PopupMenuItem(value: 'piles', child: Text('Rename piles')),
                  if (b['status'] == 'open') const PopupMenuItem(value: 'close', child: Text(S.closeBooth)),
                ],
              ),
            ],
          ),
          body: widget.mode == 'line'
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(T.gutter),
                  child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: T.maxContent), child: linePanel)))
              : widget.mode == 'list'
                  ? list
                  : wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 360, child: SingleChildScrollView(padding: const EdgeInsets.all(T.gutter), child: linePanel)),
                  const VerticalDivider(width: 1),
                  Expanded(child: list),
                ])
              : CustomScrollView(slivers: [
                  SliverPadding(padding: const EdgeInsets.all(T.gutter), sliver: SliverToBoxAdapter(child: linePanel)),
                  SliverFillRemaining(hasScrollBody: true, child: list),
                ]),
        );
      },
    );
  }

  Widget _shortlist(BuildContext context, Json v, Future<void> Function() reload) {
    final settings = v['settings'] as Json;
    final piles = (((v['booth'] as Json)['piles'] as List?) ?? []).cast<String>();
    final sections = ((v['sections'] as List?) ?? []).cast<Json>();
    final drift = v['drift'] as Json?;
    final sl = v['second_look'] as Json;
    final hfLp = ((sl['high_fit_low_pile'] as List?) ?? []).cast<Json>();
    final lfHp = ((sl['low_fit_high_pile'] as List?) ?? []).cast<Json>();
    final strong = ((v['strong_unmet'] as List?) ?? []).cast<Json>();

    bool keep(Json c) {
      if (pileFilter.isNotEmpty && !pileFilter.contains(c['pile'])) return false;
      if (minFit > 0 && (c['fit'] as num) < minFit) return false;
      if (section.isNotEmpty && c['section'] != section) return false;
      return true;
    }

    CandidateCard card(Json c, {Widget? handle}) => CandidateCard(
          c: c,
          piles: piles,
          blind: blind,
          boothId: widget.boothId,
          keyQuery: q,
          handle: handle,
        );

    final header = <Widget>[
      Card(
        color: T.infoBg,
        child: Padding(
          padding: const EdgeInsets.all(T.s3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(S.suggestedOrder, style: TextStyle(fontWeight: FontWeight.w800, fontSize: T.h3)),
            const SizedBox(height: T.s1),
            Text(settings['formula'] as String, style: const TextStyle(fontSize: T.small)),
            const Text('${S.arrivalInfo} Your stars and piles are private and never change the Score.', style: TextStyle(fontSize: T.small, color: T.muted)),
          ]),
        ),
      ),
      const SizedBox(height: T.s3),
      Wrap(spacing: T.s2, runSpacing: T.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<SortMode>(
          segments: const [
            ButtonSegment(value: SortMode.suggested, label: Text('Suggested')),
            ButtonSegment(value: SortMode.stars, label: Text('My stars')),
            ButtonSegment(value: SortMode.mine, label: Text('My order')),
          ],
          selected: {sort},
          onSelectionChanged: (s) => setState(() => sort = s.first),
        ),
        FilterChip(label: const Text(S.blindReview), selected: blind, onSelected: (x) => setState(() => blind = x)),
      ]),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.tune),
        title: Text(_activeFilters == 0 ? 'Filters and export' : 'Filters and export ($_activeFilters on)'),
        childrenPadding: const EdgeInsets.only(bottom: T.s2),
        expandedAlignment: Alignment.centerLeft,
        children: [
      Wrap(spacing: T.s2, runSpacing: T.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final p in piles)
          FilterChip(
            label: Text(p),
            selected: pileFilter.contains(p),
            onSelected: (x) => setState(() => x ? pileFilter.add(p) : pileFilter.remove(p)),
          ),
        DropdownButton<double>(
          value: minFit,
          items: const [
            DropdownMenuItem(value: 0, child: Text('Any fit')),
            DropdownMenuItem(value: 0.5, child: Text('Fit 0.5+')),
            DropdownMenuItem(value: 0.7, child: Text('Fit 0.7+')),
            DropdownMenuItem(value: 0.85, child: Text('Fit 0.85+')),
          ],
          onChanged: (x) => setState(() => minFit = x ?? 0),
        ),
        DropdownButton<String>(
          value: section,
          items: const [
            DropdownMenuItem(value: '', child: Text('All sections')),
            DropdownMenuItem(value: 'met', child: Text(S.metSection)),
            DropdownMenuItem(value: 'waited', child: Text(S.waitedSection)),
            DropdownMenuItem(value: 'sent', child: Text(S.sentSection)),
          ],
          onChanged: (x) => setState(() => section = x ?? ''),
        ),
        OutlinedButton.icon(
            onPressed: () => api.openUrl('/api/recruiter/${widget.boothId}/export.csv?${_filterQuery()}'),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('CSV')),
        OutlinedButton.icon(
            onPressed: () => api.openUrl('/api/recruiter/${widget.boothId}/export.zip?${_filterQuery()}'),
            icon: const Icon(Icons.folder_zip_outlined),
            label: const Text('CSV + resume PDFs')),
        if (_activeFilters > 0)
          TextButton(
              onPressed: () => setState(() {
                    pileFilter = {};
                    minFit = 0;
                    section = '';
                  }),
              child: const Text('Clear filters')),
      ]),
        ],
      ),
      if (drift != null) ...[
        const SizedBox(height: T.s3),
        Banner2(text: drift['message'] as String, icon: Icons.trending_down, color: T.warning, bg: T.warningBg),
      ],
      if (hfLp.isNotEmpty || lfHp.isNotEmpty) ...[
        const SizedBox(height: T.s3),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.flip_outlined, color: T.warning),
            title: Text('${S.secondLook}: ${hfLp.length + lfHp.length} to check'),
            subtitle: const Text('First impressions vs. blind fit. Nothing changes automatically.'),
            children: [
              for (final x in hfLp)
                ListTile(
                  dense: true,
                  title: Text('${blind ? 'Candidate' : x['name']} · fit ${pct(x['fit'] as num)} · in ${x['pile']}'),
                  subtitle: Text('High fit, low pile. ${x['prompt']}'),
                ),
              for (final x in lfHp)
                ListTile(
                  dense: true,
                  title: Text('${blind ? 'Candidate' : x['name']} · fit ${pct(x['fit'] as num)} · in ${x['pile']}'),
                  subtitle: Text('Low fit, high pile. ${x['prompt']}'),
                ),
            ],
          ),
        ),
      ],
    ];

    if (sort != SortMode.suggested) {
      final all = [for (final s in sections) ...((s['items'] as List).cast<Json>())].where(keep).toList();
      if (sort == SortMode.stars) {
        all.sort((a, b) {
          final s = ((b['stars'] as num?) ?? 0).compareTo((a['stars'] as num?) ?? 0);
          return s != 0 ? s : (a['rank'] as int).compareTo(b['rank'] as int);
        });
        return ListView(padding: const EdgeInsets.all(T.gutter), children: [
          ...header,
          SectionTitle('Sorted by your stars', sub: '${all.length} candidates'),
          for (final c in all) Padding(padding: const EdgeInsets.only(bottom: T.s2), child: card(c)),
        ]);
      }
      all.sort((a, b) {
        final ma = a['manual_rank'] as num?, mb = b['manual_rank'] as num?;
        if (ma != null && mb != null) return ma.compareTo(mb);
        if (ma != null) return -1;
        if (mb != null) return 1;
        return (a['rank'] as int).compareTo(b['rank'] as int);
      });
      return ReorderableListView(
        padding: const EdgeInsets.all(T.gutter),
        buildDefaultDragHandles: false,
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...header, const SectionTitle('Your order', sub: 'Drag to reorder. Saved to your private list.')]),
        onReorderItem: (from, to) async {
          final x = all.removeAt(from);
          all.insert(to, x);
          setState(() {});
          await api.post('/api/recruiter/${widget.boothId}/order?$q', {
            'student_ids': [for (final c in all) (c['student'] as Json)['id']]
          });
          await reload();
        },
        children: [
          for (final (i, c) in all.indexed)
            Padding(
              key: ValueKey((c['student'] as Json)['id']),
              padding: const EdgeInsets.only(bottom: T.s2),
              child: card(c, handle: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator, color: T.muted))),
            ),
        ],
      );
    }

    return ListView(padding: const EdgeInsets.all(T.gutter), children: [
      ...header,
      for (final s in sections)
        if (section.isEmpty || section == s['key']) ...[
          SectionTitle('${s['label']} (${(s['items'] as List).length})',
              sub: switch (s['key']) {
                'met' => 'Verified by your scan or "Met". Shown first.',
                'waited' => 'In your line when it closed. Their wait is credited.',
                _ => 'Drops and Fair Play matches.',
              }),
          if (s['key'] == 'sent' && strong.isNotEmpty && !blind)
            Card(
              color: T.accent.withValues(alpha: 0.25),
              child: Padding(
                padding: const EdgeInsets.all(T.s3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${S.strongUnmet} (${strong.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Text('Fit 0.85+. They could not stay or reach you; their resume is here.', style: TextStyle(fontSize: T.small)),
                  const SizedBox(height: T.s2),
                  Wrap(spacing: T.s2, runSpacing: T.s2, children: [
                    for (final c in strong) Pill('${(c['student'] as Json)['name']} · fit ${c['fit_pct']}', bg: T.surface),
                  ]),
                ]),
              ),
            ),
          if ((s['items'] as List).isEmpty)
            const Padding(padding: EdgeInsets.all(T.s3), child: Text('No one yet.', style: TextStyle(color: T.muted))),
          for (final c in (s['items'] as List).cast<Json>().where(keep))
            Padding(padding: const EdgeInsets.only(bottom: T.s2), child: card(c)),
        ],
    ]);
  }
}

class _LinePanel extends StatelessWidget {
  final Json view;
  final void Function(String studentId) onMet;
  final VoidCallback onNumber;
  final void Function(Json req, bool accept) onRespond;
  final void Function(String studentId, String name) onNoShow;
  const _LinePanel({required this.view, required this.onMet, required this.onNumber, required this.onRespond, required this.onNoShow});

  @override
  Widget build(BuildContext context) {
    final line = ((view['line'] as List?) ?? []).cast<Json>();
    final counts = view['counts'] as Json;
    final open = (view['booth'] as Json)['status'] == 'open';
    final top = line.isEmpty ? null : line.first;
    final requests = ((view['card_requests'] as List?) ?? []).cast<Json>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (requests.isNotEmpty) ...[
        Text('Card requests (${requests.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: T.h3)),
        const Text('Students you are talking to sent their card. Accept to swap cards.', style: TextStyle(fontSize: T.tiny, color: T.muted)),
        const SizedBox(height: T.s2),
        for (final r in requests)
          Card(
            color: T.successBg,
            child: Padding(
              padding: const EdgeInsets.all(T.s3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  PixelAvatar((r['student'] as Json)['avatar'] as String, size: 40),
                  const SizedBox(width: T.s2),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${(r['student'] as Json)['name']}  #${(r['student'] as Json)['number']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${(r['student'] as Json)['major']}${r['in_line'] == true ? ' · in your line' : ''}', style: const TextStyle(fontSize: T.small)),
                      if (((r['student'] as Json)['bio'] as String?)?.isNotEmpty == true)
                        Text('${(r['student'] as Json)['bio']}', style: const TextStyle(fontSize: T.tiny, color: T.muted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: T.s2),
                Row(children: [
                  Expanded(child: FilledButton(onPressed: () => onRespond(r, true), child: const Text('Accept'))),
                  const SizedBox(width: T.s2),
                  OutlinedButton(onPressed: () => onRespond(r, false), child: const Text('Decline')),
                ]),
              ]),
            ),
          ),
        const SizedBox(height: T.s4),
      ],
      Text('${line.length}', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, height: 1)),
      Text(open ? 'in your line now' : 'Line closed', style: const TextStyle(fontWeight: FontWeight.w700)),
      Text('~${view['avg_service_min']} min per conversation today · ${counts['met']} met · ${counts['sent']} resumes',
          style: const TextStyle(fontSize: T.small, color: T.muted)),
      const SizedBox(height: T.s4),
      if (top != null)
        Card(
          color: T.accent.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(T.s3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Next in line', style: TextStyle(fontSize: T.tiny, fontWeight: FontWeight.w700, color: T.muted)),
              const SizedBox(height: T.s2),
              Row(children: [
                PixelAvatar((top['student'] as Json)['avatar'] as String, size: 48),
                const SizedBox(width: T.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((top['student'] as Json)['name'] as String, style: const TextStyle(fontSize: T.h2, fontWeight: FontWeight.w800)),
                    Text('${(top['student'] as Json)['major']} · waited ${top['waited_min']} min · fit ${top['fit_pct']}',
                        style: const TextStyle(fontSize: T.small)),
                  ]),
                ),
              ]),
              const SizedBox(height: T.s3),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onMet((top['student'] as Json)['id'] as String),
                    icon: const Icon(Icons.handshake_outlined),
                    label: const Text(S.met),
                  ),
                ),
                const SizedBox(width: T.s2),
                OutlinedButton(
                  onPressed: () => onNoShow((top['student'] as Json)['id'] as String, (top['student'] as Json)['name'] as String),
                  child: const Text('Not here'),
                ),
              ]),
            ]),
          ),
        )
      else
        const Card(child: Padding(padding: EdgeInsets.all(T.s4), child: Text('No one in line.', style: TextStyle(color: T.muted)))),
      const SizedBox(height: T.s2),
      OutlinedButton.icon(onPressed: onNumber, icon: const Icon(Icons.dialpad), label: const Text('Enter student number')),
      const SizedBox(height: T.s1),
      const Text('Talking to someone not at the top? Accept their card above, or type the number on their card.',
          style: TextStyle(fontSize: T.tiny, color: T.muted)),
      if (line.length > 1) ...[
        const SizedBox(height: T.s4),
        const Text('Up next', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final e in line.skip(1).take(8))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: PixelAvatar((e['student'] as Json)['avatar'] as String, size: 28),
            title: Text((e['student'] as Json)['name'] as String),
            subtitle: Text('waited ${e['waited_min']} min'),
          ),
        if (line.length > 9) Text('+ ${line.length - 9} more', style: const TextStyle(color: T.muted)),
      ],
    ]);
  }
}
