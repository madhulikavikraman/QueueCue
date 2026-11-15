import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';
import '../rolodex/rolodex_tab.dart' show RolodexCard;

/// "My card": your number + business card, add people by number, accept
/// requests, and every card you have swapped. No QR codes.
class CardTab extends ConsumerStatefulWidget {
  const CardTab({super.key});
  @override
  ConsumerState<CardTab> createState() => _CardTabState();
}

class _CardTabState extends ConsumerState<CardTab> {
  final numberC = TextEditingController();
  bool sending = false;
  int seg = 0; // rolodex: 0 recruiters, 1 students

  Api get api => ref.read(apiProvider);

  Future<void> _send(Future<void> Function() reload) async {
    if (numberC.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      final r = await api.post('/api/me/cards/request', {'number': numberC.text.trim(), 'whose': (int.tryParse(numberC.text.trim()) ?? 0) < 100 ? 'booth' : 'person'});
      numberC.clear();
      if (mounted) toast(context, r['message'] as String);
      await reload();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _respond(int id, bool accept, Future<void> Function() reload) async {
    try {
      final r = await api.post('/api/me/cards/$id/${accept ? 'accept' : 'decline'}');
      if (mounted) toast(context, r['message'] as String);
      await reload();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _editCard(Json me, Future<void> Function() reload) async {
    final interests = TextEditingController(text: me['interests'] as String? ?? '');
    final bio = TextEditingController(text: me['bio'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit my card'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: interests, decoration: const InputDecoration(labelText: 'Interests', hintText: 'LLM serving, rocketry, chess')),
            const SizedBox(height: T.s3),
            TextField(controller: bio, minLines: 2, maxLines: 4, maxLength: 160, decoration: const InputDecoration(labelText: 'About me (one or two lines)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await api.patch('/api/me', {'interests': interests.text.trim(), 'bio': bio.text.trim()});
    await reload();
  }

  static Json _recruiterAsCard(Json r) => {
        'number': r['number'],
        'tag': 'RECRUITER',
        'name': r['name'],
        'title': 'Recruiter at ${r['company']}',
        'subtitle': 'Swapped at booth ${r['booth_number']}${r['met_at'] != null ? ', ${hhmm(r['met_at'])}' : ''}',
        'email': r['email'],
        'avatar': 'owl',
      };

  @override
  Widget build(BuildContext context) => LiveBuilder(
        fetch: (api) async => {...await api.get('/api/me/cards'), 'rolodex': (await api.get('/api/me/rolodex'))['items']},
        listen: (t) => t.startsWith('student:'),
        fallbackPoll: const Duration(seconds: 10),
        builder: (context, d, reload) {
          final me = d['me'] as Json;
          final incoming = ((d['incoming'] as List?) ?? []).cast<Json>();
          final outgoing = ((d['outgoing'] as List?) ?? []).cast<Json>();
          final friends = ((d['friends'] as List?) ?? []).cast<Json>();
          final recruiters = ((d['recruiters'] as List?) ?? []).cast<Json>();
          final rolo = ((d['rolodex'] as List?) ?? []).cast<Json>();
          return PageBody(onRefresh: reload, children: [
              const BigHeading('My card'),
              BusinessCard(card: me, mine: true, onEdit: () => _editCard(me, reload)),
              const SizedBox(height: T.s2),
              Text('Your number is ${me['number']}. Tell people; they type it to ask for your card.',
                  style: const TextStyle(color: T.muted, fontSize: T.small)),
              const SizedBox(height: T.s5),
              const BigHeading("Ask for someone's card"),
              const Text(
                'Type a student\'s or recruiter\'s card number, or a tent number (1 to 12) to reach that '
                'booth\'s recruiter. Cards swap on both phones when they accept.',
                style: TextStyle(color: T.muted, fontSize: T.body, height: 1.5),
              ),
              const SizedBox(height: T.s4),
              Wrap(spacing: T.s3, runSpacing: T.s3, crossAxisAlignment: WrapCrossAlignment.end, children: [
                SizedBox(
                  width: 260,
                  child: _Labeled('Card or tent number', TextField(
                    controller: numberC,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Card no. or tent no.',
                      border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: T.ink, width: 2)),
                      enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: T.ink, width: 2)),
                    ),
                    onSubmitted: (_) => _send(reload),
                  )),
                ),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: T.ink, shape: const RoundedRectangleBorder()),
                    onPressed: sending ? null : () => _send(reload),
                    child: const Text('Share my card', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ]),
              if (incoming.isNotEmpty) ...[
                const SizedBox(height: T.s5),
                BigHeading('Asking for your card (${incoming.length})'),
                for (final r in incoming)
                  Padding(
                    padding: const EdgeInsets.only(bottom: T.s5),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      BusinessCard(card: r['card'] as Json),
                      const SizedBox(height: T.s3),
                      Row(children: [
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: T.ink, shape: const RoundedRectangleBorder()),
                          onPressed: () => _respond(r['id'] as int, true, reload),
                          child: const Text('Accept and swap cards'),
                        ),
                        const SizedBox(width: T.s2),
                        TextButton(onPressed: () => _respond(r['id'] as int, false, reload), child: const Text('Decline')),
                      ]),
                    ]),
                  ),
              ],
              if (outgoing.isNotEmpty) ...[
                const SizedBox(height: T.s4),
                for (final o in outgoing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: T.s1),
                    child: Text(
                      o['kind'] == 'friend'
                          ? 'Waiting for No. ${(o['card'] as Json)['number']} (${(o['card'] as Json)['name']}) to accept'
                          : 'Waiting for ${(o['booth'] as Json)['name']} (booth ${(o['booth'] as Json)['number']}) to accept',
                      style: const TextStyle(color: T.muted),
                    ),
                  ),
              ],
              const SizedBox(height: T.s5),
              const BigHeading('Rolodex'),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text('Recruiters (${recruiters.length})'), icon: const Icon(Icons.badge_outlined)),
                  ButtonSegment(value: 1, label: Text('Students (${friends.length})'), icon: const Icon(Icons.school_outlined)),
                ],
                selected: {seg},
                onSelectionChanged: (x) => setState(() => seg = x.first),
              ),
              const SizedBox(height: T.s4),
              if (seg == 0 && recruiters.isEmpty)
                const Text('No recruiters yet. At a tent, tap "Send my card to the recruiter", or type their number above.',
                    style: TextStyle(color: T.muted)),
              if (seg == 0)
                for (final r in recruiters)
                  Padding(
                    padding: const EdgeInsets.only(bottom: T.s4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      BusinessCard(card: _recruiterAsCard(r)),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        leading: const Icon(Icons.edit_note),
                        title: const Text('Notes and follow-up email'),
                        children: [
                          for (final it in rolo.where((x) => x['booth_id'] == r['booth_id']))
                            RolodexCard(item: it, reload: reload),
                        ],
                      ),
                    ]),
                  ),
              if (seg == 1 && friends.isEmpty) const Text('No students yet. Swap numbers with a friend.', style: TextStyle(color: T.muted)),
              if (seg == 1)
                for (final f in friends) Padding(padding: const EdgeInsets.only(bottom: T.s4), child: BusinessCard(card: f)),
              const SizedBox(height: T.s2),
              const Text('What a swap shows is up to you: tap Edit card on your card.', style: TextStyle(color: T.muted)),
            ]);
        },
      );
}

/// Business card in the "badge" style: No. ####, tag box, big uppercase name,
/// title, school line, links, and a hard orange offset shadow.
class BusinessCard extends StatelessWidget {
  final Json card;
  final bool mine;
  final VoidCallback? onEdit;
  const BusinessCard({super.key, required this.card, this.mine = false, this.onEdit});

  static const _shadow = Color(0xFFF0A060);

  String get _tag {
    final t = card['tag'] as String?;
    if (t != null) return t;
    final interests = (card['interests'] as String?)?.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList() ?? [];
    return interests.isNotEmpty ? interests.first.toUpperCase() : 'STUDENT';
  }

  @override
  Widget build(BuildContext context) {
    final title = (card['title'] as String?) ?? (card['bio'] as String?)?.trim() ?? '';
    final subtitle = (card['subtitle'] as String?) ?? '${card['degree'] ?? ''} ${card['major'] ?? ''}'.trim();
    final email = card['email'] as String?;
    final linkedin = card['linkedin'] as String?;
    final interests = (card['interests'] as String?)?.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).skip(1).toList() ?? [];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Container(
        margin: const EdgeInsets.only(right: 16, bottom: 16),
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: _shadow, offset: Offset(16, 16))]),
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFFFFFDF8), border: Border.all(color: T.ink, width: 2.5)),
          padding: const EdgeInsets.fromLTRB(T.s5, T.s5, T.s5, T.s5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text('${card['number_label'] ?? 'NO.'} ${card['number'] ?? ''}',
                    style: const TextStyle(fontFamily: 'monospace', letterSpacing: 2, color: T.muted, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: T.s3, vertical: 5),
                decoration: BoxDecoration(border: Border.all(color: T.ink, width: 2)),
                child: Text(_tag, style: const TextStyle(fontFamily: 'monospace', letterSpacing: 2, fontSize: 13, color: T.ink)),
              ),
            ]),
            const SizedBox(height: T.s2),
            Text((card['name'] as String? ?? '').toUpperCase(),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -0.8, color: T.ink)),
            if (title.isNotEmpty) ...[
              const SizedBox(height: T.s2),
              Text(title, style: const TextStyle(fontSize: 19, color: T.ink, height: 1.35)),
            ],
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 16, color: T.muted)),
            ],
            if (interests.isNotEmpty) ...[
              const SizedBox(height: T.s2),
              Text(interests.join(' · '), style: const TextStyle(fontSize: 14, color: T.muted)),
            ],
            if ((email?.isNotEmpty ?? false) || (linkedin?.isNotEmpty ?? false)) ...[
              const SizedBox(height: T.s4),
              Wrap(spacing: T.s4, runSpacing: T.s2, children: [
                if (email != null && email.isNotEmpty) _Link(email, 'mailto:$email'),
                if (linkedin != null && linkedin.isNotEmpty)
                  _Link('LinkedIn', linkedin.startsWith('http') ? linkedin : 'https://$linkedin'),
              ]),
            ],
            if (mine && onEdit != null) ...[
              const SizedBox(height: T.s3),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit card')),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Link extends ConsumerWidget {
  final String text;
  final String url;
  const _Link(this.text, this.url);
  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
        onTap: () => ref.read(apiProvider).openUrl(url),
        child: Text(text,
            style: const TextStyle(fontSize: 17, color: Color(0xFFA34A12), decoration: TextDecoration.underline, decorationColor: Color(0xFFA34A12))),
      );
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled(this.label, this.child);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: T.s2),
        child,
      ]);
}

/// Heavy uppercase section heading.
class BigHeading extends StatelessWidget {
  final String text;
  const BigHeading(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: T.s2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.05, color: T.ink)),
      );
}

/// Faint graph-paper background.
class GridPaper extends StatelessWidget {
  final Widget child;
  const GridPaper({super.key, required this.child});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter(), child: child);
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFEFE3CF)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
