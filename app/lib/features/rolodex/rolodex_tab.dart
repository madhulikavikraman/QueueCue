import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/platform/recorder.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';
import '../../core/widgets/states.dart';

class RolodexTab extends ConsumerWidget {
  const RolodexTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => LiveBuilder(
        fetch: (api) => api.get('/api/me/rolodex'),
        listen: (t) => t.startsWith('student:'),
        builder: (context, d, reload) {
          final items = ((d['items'] as List?) ?? []).cast<Json>();
          return PageBody(onRefresh: reload, children: [
            Text(S.rolodexTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: T.s1),
            Text('Everyone who confirmed a conversation with you, with their card.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: T.s3),
            if (items.isEmpty) const EmptyState(icon: Icons.contacts_outlined, title: 'No conversations yet', body: S.rolodexEmpty),
            for (final it in items) Padding(padding: const EdgeInsets.only(bottom: T.s3), child: RolodexCard(item: it, reload: reload)),
          ]);
        },
      );
}

class RolodexCard extends ConsumerStatefulWidget {
  final Json item;
  final Future<void> Function() reload;
  const RolodexCard({super.key, required this.item, required this.reload});
  @override
  ConsumerState<RolodexCard> createState() => _RolodexCardState();
}

class _RolodexCardState extends ConsumerState<RolodexCard> {
  late final noteC = TextEditingController(text: widget.item['note'] as String? ?? '');
  String? job;
  String? emailJob;
  String? error;
  late final subj = TextEditingController(text: (widget.item['email'] as Json?)?['subject'] as String? ?? '');
  late final body = TextEditingController(text: (widget.item['email'] as Json?)?['body'] as String? ?? '');

  String get boothId => widget.item['booth_id'] as String;
  Api get api => ref.read(apiProvider);

  @override
  void didUpdateWidget(covariant RolodexCard old) {
    super.didUpdateWidget(old);
    final n = widget.item['note'] as String?;
    if (n != null && n != old.item['note'] && noteC.text.trim().isEmpty) noteC.text = n;
    final e = widget.item['email'] as Json?;
    if (e != null && body.text.isEmpty) {
      subj.text = e['subject'] as String? ?? '';
      body.text = e['body'] as String? ?? '';
    }
  }

  Future<void> _saveNote() async {
    try {
      await api.post('/api/me/rolodex/$boothId/note', {'note': noteC.text});
      if (mounted) toast(context, 'Note saved.');
      await widget.reload();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _draft() async {
    if (noteC.text.trim().isNotEmpty && noteC.text.trim() != (widget.item['note'] ?? '')) await _saveNote();
    final r = await api.post('/api/me/rolodex/$boothId/email');
    setState(() => emailJob = r['job_id'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.item['card'] as Json;
    final sent = widget.item['email_sent_at'] != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(T.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.badge_outlined, color: T.brand),
            const SizedBox(width: T.s2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${card['name']} · ${card['company']}', style: Theme.of(context).textTheme.titleMedium),
                Text('${card['email']} · met ${hhmm(widget.item['met_at'])} at Booth ${card['booth_number']}', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: T.s3),
          TextField(
            controller: noteC,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: S.addNote, hintText: 'What did they say? What did they ask you to do?'),
          ),
          const SizedBox(height: T.s2),
          if (job != null)
            JobProgress(
              jobId: job!,
              compact: true,
              onDone: (j) async {
                noteC.text = ((j['result'] as Json?)?['note'] as String?) ?? noteC.text;
                setState(() => job = null);
                await widget.reload();
              },
              onError: (m) => setState(() {
                job = null;
                error = m;
              }),
            )
          else
            Wrap(spacing: T.s2, runSpacing: T.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              VoiceRecorder(
                maxSeconds: 15,
                startLabel: S.recordNote,
                onDone: (b64, _) async {
                  final r = await api.post('/api/me/rolodex/$boothId/note', {'wav_base64': b64});
                  setState(() => job = r['job_id'] as String);
                },
                onError: (m) => setState(() => error = m),
              ),
              TextButton(onPressed: _saveNote, child: const Text('Save typed note')),
            ]),
          if (widget.item['note_at'] != null)
            Text('Noted ${agoMin(widget.item['note_at'])}', style: const TextStyle(fontSize: T.tiny, color: T.muted)),
          if (error != null) ...[const SizedBox(height: T.s2), Banner2(text: error!, color: T.danger, bg: T.dangerBg)],
          const Divider(height: T.s5),
          if (emailJob != null)
            JobProgress(
              jobId: emailJob!,
              onDone: (j) {
                final e = j['result'] as Json? ?? {};
                setState(() {
                  subj.text = e['subject'] as String? ?? '';
                  body.text = e['body'] as String? ?? '';
                  emailJob = null;
                });
              },
              onError: (m) => setState(() {
                emailJob = null;
                error = m;
              }),
            )
          else if (body.text.isEmpty)
            FilledButton.icon(
              onPressed: noteC.text.trim().isEmpty ? null : _draft,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text(S.draftEmail),
            )
          else ...[
            Text('Follow-up email', style: Theme.of(context).textTheme.titleMedium),
            const Text('From your note + your resume, in your voice. Edit before sending.', style: TextStyle(fontSize: T.tiny, color: T.muted)),
            const SizedBox(height: T.s2),
            TextField(controller: subj, decoration: const InputDecoration(labelText: 'Subject')),
            const SizedBox(height: T.s2),
            TextField(controller: body, minLines: 6, maxLines: 14, decoration: const InputDecoration(labelText: 'Body')),
            const SizedBox(height: T.s2),
            Wrap(spacing: T.s2, runSpacing: T.s2, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: 'Subject: ${subj.text}\n\n${body.text}'));
                  if (context.mounted) toast(context, 'Copied.');
                },
                icon: const Icon(Icons.copy),
                label: const Text(S.copy),
              ),
              OutlinedButton.icon(
                onPressed: () => api.openUrl(Uri(
                  scheme: 'mailto',
                  path: card['email'] as String? ?? '',
                  query: 'subject=${Uri.encodeComponent(subj.text)}&body=${Uri.encodeComponent(body.text)}',
                ).toString()),
                icon: const Icon(Icons.mail_outline),
                label: const Text(S.openMail),
              ),
              if (!sent)
                FilledButton.icon(
                  onPressed: () async {
                    final r = await api.post('/api/me/rolodex/$boothId/sent');
                    if (context.mounted) toast(context, r['message'] as String);
                    await widget.reload();
                  },
                  icon: const Icon(Icons.check),
                  label: const Text(S.iSentIt),
                )
              else
                Pill('Sent ${hhmm(widget.item['email_sent_at'])}', fg: T.success, bg: T.successBg, icon: Icons.check),
              TextButton(onPressed: _draft, child: const Text('Redraft')),
            ]),
          ],
        ]),
      ),
    );
  }
}
