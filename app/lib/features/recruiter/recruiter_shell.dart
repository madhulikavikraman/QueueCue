import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';
import '../plan/qr_tab.dart' show BusinessCard, BigHeading;
import 'quick_rate.dart';
import 'recruiter_edit.dart';
import 'recruiter_page.dart';

/// The recruiter app: separate from the student app, with its own tabs.
class RecruiterShell extends ConsumerStatefulWidget {
  final RecruiterAuth auth;
  final int initialTab;
  const RecruiterShell({super.key, required this.auth, this.initialTab = 0});
  @override
  ConsumerState<RecruiterShell> createState() => _RecruiterShellState();
}

class _RecruiterShellState extends ConsumerState<RecruiterShell> {
  late int tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final a = widget.auth;
    final pages = [
      RecruiterPage(boothId: a.boothId, keyParam: a.key, mode: 'line'),
      RecruiterPage(boothId: a.boothId, keyParam: a.key, mode: 'list'),
      RecruiterCardsTab(auth: a),
      _RecruiterMe(auth: a),
    ];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt), label: 'Line'),
          NavigationDestination(icon: Icon(Icons.format_list_numbered), label: 'Candidates'),
          NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'Cards'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
      ),
    );
  }
}

Json recruiterAsCard(Json r, {String? subtitle}) => {
      'number': r['number'],
      'tag': 'RECRUITER',
      'name': r['name'],
      'title': '${(r['title'] as String?)?.isNotEmpty == true ? r['title'] : 'Recruiter'} at ${r['company']}',
      'subtitle': subtitle ?? 'Booth ${r['booth_number']}',
      'email': r['email'],
      'avatar': 'owl',
    };

class RecruiterCardsTab extends ConsumerStatefulWidget {
  final RecruiterAuth auth;
  const RecruiterCardsTab({super.key, required this.auth});
  @override
  ConsumerState<RecruiterCardsTab> createState() => _RecruiterCardsTabState();
}

class _RecruiterCardsTabState extends ConsumerState<RecruiterCardsTab> {
  final numberC = TextEditingController();
  int seg = 0; // 0 students, 1 recruiters
  bool busy = false;

  Api get api => ref.read(apiProvider);
  String get base => '/api/recruiter/${widget.auth.boothId}';
  String get q => 'key=${Uri.encodeComponent(widget.auth.key)}';

  Future<List<String>> _piles() async {
    final v = await api.get('$base?$q');
    return (((v['booth'] as Json)['piles'] as List?) ?? []).cast<String>();
  }

  Future<void> _share(Future<void> Function() reload, {bool group = false}) async {
    final n = numberC.text.trim();
    if (n.isEmpty) return;
    setState(() => busy = true);
    try {
      final r = await api.post('$base/cards/share?$q', {'number': n, 'group': group});
      numberC.clear();
      if (!mounted) return;
      if (r['student'] != null) {
        // Swapped with a student: rate them now.
        await showQuickRate(context, ref,
            boothId: widget.auth.boothId, keyQuery: q, student: r['student'] as Json, piles: await _piles());
      } else {
        toast(context, r['message'] as String);
      }
      await reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.data['needs_group'] == true) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text(S.groupChat),
            content: Text(e.message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, group chat')),
            ],
          ),
        );
        if (ok == true) {
          numberC.text = n;
          await _share(reload, group: true);
        }
      } else {
        toast(context, e.message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LiveBuilder(
        fetch: (api) => api.get('$base/cards?$q'),
        listen: (t) => t == 'booth:${widget.auth.boothId}',
        fallbackPoll: const Duration(seconds: 10),
        builder: (context, d, reload) {
          final me = d['me'] as Json;
          final inPeers = ((d['incoming_peers'] as List?) ?? []).cast<Json>();
          final inStudents = ((d['incoming_students'] as List?) ?? []).cast<Json>();
          final outgoing = ((d['outgoing'] as List?) ?? []).cast<Json>();
          final peers = ((d['peers'] as List?) ?? []).cast<Json>();
          final students = ((d['students'] as List?) ?? []).cast<Json>();
          return Scaffold(
            body: SafeArea(
              child: PageBody(onRefresh: reload, children: [
                const BigHeading('My card'),
                BusinessCard(
                  card: recruiterAsCard(me),
                  mine: true,
                  onEdit: () async {
                    await showRecruiterEdit(context, ref, widget.auth);
                    await reload();
                  },
                ),
                Text('Your number is ${me['number']}. Students and other recruiters type it to ask for your card.',
                    style: const TextStyle(color: T.muted, fontSize: T.small)),
                const SizedBox(height: T.s5),
                const BigHeading('Swap cards'),
                const Text("Type a student's or a recruiter's card number. A student swap counts as meeting them; you rate them next.",
                    style: TextStyle(color: T.muted)),
                const SizedBox(height: T.s3),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: numberC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Card number (3 or 4 digits)'),
                      onSubmitted: (_) => _share(reload),
                    ),
                  ),
                  const SizedBox(width: T.s2),
                  SizedBox(height: 52, child: FilledButton(onPressed: busy ? null : () => _share(reload), child: const Text('Share my card'))),
                ]),
                if (inStudents.isNotEmpty || inPeers.isNotEmpty) ...[
                  const SizedBox(height: T.s5),
                  BigHeading('Asking for your card (${inStudents.length + inPeers.length})'),
                  for (final r in inStudents)
                    _Request(
                      card: {...(r['student'] as Json), 'subtitle': r['in_line'] == true ? 'Student · in your line' : 'Student'},
                      onAccept: () async {
                        try {
                          final res = await api.post('$base/requests/${r['id']}/accept?$q', {'group': true});
                          if (!context.mounted) return;
                          await showQuickRate(context, ref,
                              boothId: widget.auth.boothId, keyQuery: q, student: res['student'] as Json, piles: await _piles());
                          await reload();
                        } on ApiException catch (e) {
                          if (context.mounted) toast(context, e.message);
                        }
                      },
                      onDecline: () async {
                        await api.post('$base/requests/${r['id']}/decline?$q');
                        await reload();
                      },
                    ),
                  for (final r in inPeers)
                    _Request(
                      card: recruiterAsCard(r['card'] as Json),
                      onAccept: () async {
                        final res = await api.post('$base/peers/${r['id']}/accept?$q');
                        if (context.mounted) toast(context, res['message'] as String);
                        await reload();
                      },
                      onDecline: () async {
                        await api.post('$base/peers/${r['id']}/decline?$q');
                        await reload();
                      },
                    ),
                ],
                for (final o in outgoing)
                  Padding(
                    padding: const EdgeInsets.only(top: T.s2),
                    child: Text('Waiting for ${o['name']} (${o['company']}) to accept', style: const TextStyle(color: T.muted)),
                  ),
                const SizedBox(height: T.s5),
                const BigHeading('Rolodex'),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text('Students (${students.length})'), icon: const Icon(Icons.school_outlined)),
                    ButtonSegment(value: 1, label: Text('Recruiters (${peers.length})'), icon: const Icon(Icons.badge_outlined)),
                  ],
                  selected: {seg},
                  onSelectionChanged: (x) => setState(() => seg = x.first),
                ),
                const SizedBox(height: T.s4),
                if (seg == 0 && students.isEmpty) const Text('No students yet.', style: TextStyle(color: T.muted)),
                if (seg == 1 && peers.isEmpty) const Text('No recruiters yet. Share your card with a colleague by number.', style: TextStyle(color: T.muted)),
                if (seg == 0)
                  for (final st in students)
                    Padding(
                      padding: const EdgeInsets.only(bottom: T.s4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        BusinessCard(card: {
                          ...st,
                          'title': st['bio'] ?? '',
                          'subtitle': '${st['degree'] ?? ''} ${st['major']} · fit ${st['fit_pct']} · met ${hhmm(st['met_at'])}',
                        }),
                        Wrap(spacing: T.s2, runSpacing: T.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          if ((st['stars'] as num?) != null)
                            Text('★' * (st['stars'] as num).toInt(), style: const TextStyle(color: T.warning, fontSize: 18)),
                          if (st['pile'] != null) Pill('${st['pile']}'),
                          for (final t in ((st['tags'] as List?) ?? [])) Pill('$t', bg: T.accent, fg: T.onAccent),
                          FilledButton.tonalIcon(
                            onPressed: () async => showQuickRate(context, ref,
                                boothId: widget.auth.boothId, keyQuery: q, student: st, piles: await _piles(), current: st),
                            icon: const Icon(Icons.bolt, size: 18),
                            label: const Text('Quick rate'),
                          ),
                        ]),
                      ]),
                    ),
                if (seg == 1)
                  for (final p in peers)
                    Padding(padding: const EdgeInsets.only(bottom: T.s4), child: BusinessCard(card: recruiterAsCard(p))),
              ]),
            ),
          );
        },
      );
}

class _Request extends StatelessWidget {
  final Json card;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _Request({required this.card, required this.onAccept, required this.onDecline});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: T.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BusinessCard(card: card),
          Row(children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: T.ink, shape: const RoundedRectangleBorder()),
              onPressed: onAccept,
              child: const Text('Accept and swap cards'),
            ),
            const SizedBox(width: T.s2),
            TextButton(onPressed: onDecline, child: const Text('Decline')),
          ]),
        ]),
      );
}

class _RecruiterMe extends ConsumerWidget {
  final RecruiterAuth auth;
  const _RecruiterMe({required this.auth});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiProvider);
    final q = 'key=${Uri.encodeComponent(auth.key)}';
    final base = '/api/recruiter/${auth.boothId}';
    return Scaffold(
      body: SafeArea(
        child: PageBody(children: [
          BigHeading((ref.watch(recruiterProvider)?.name ?? auth.name).isEmpty ? 'Recruiter' : (ref.watch(recruiterProvider)?.name ?? auth.name)),
          Text(ref.watch(recruiterProvider)?.company ?? auth.company, style: const TextStyle(color: T.muted)),
          const SizedBox(height: T.s4),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit my card and booth'),
                subtitle: const Text('Name, title, company, role, visa sponsorship'),
                onTap: () => showRecruiterEdit(context, ref, auth),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change sign-in email or password'),
                onTap: () => showRecruiterEdit(context, ref, auth, credentials: true),
              ),
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('Download top rated (over 3.5 stars)'),
                subtitle: const Text('CSV + resume PDFs'),
                onTap: () => api.openUrl('$base/export.zip?$q&min_stars=3.5'),
              ),
              ListTile(
                leading: const Icon(Icons.table_view_outlined),
                title: const Text('Download everyone (CSV)'),
                onTap: () => api.openUrl('$base/export.csv?$q'),
              ),
              ListTile(
                leading: const Icon(Icons.laptop_mac),
                title: const Text('Open the big-screen booth view'),
                subtitle: const Text('Line and shortlist side by side, for a laptop or tablet'),
                onTap: () => context.go('/booth/${auth.boothId}?key=${auth.key}'),
              ),
              ListTile(
                leading: const Icon(Icons.door_back_door_outlined),
                title: const Text(S.closeBooth),
                subtitle: const Text('Everyone still waiting moves to your inbox with line credit'),
                onTap: () async {
                  final r = await api.post('$base/close?$q');
                  if (context.mounted) toast(context, r['message'] as String);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () async {
                  await ref.read(recruiterProvider.notifier).set(null);
                  if (context.mounted) context.go('/');
                },
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
