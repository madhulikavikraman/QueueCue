import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';

Future<void> showDropSheet(
  BuildContext context,
  WidgetRef ref, {
  required String boothId,
  required String boothName,
  required int boothNumber,
  required List<Json> resumes,
  required String? matchedResumeId,
  required String? joinToken,
  required Future<void> Function() onDone,
}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _DropSheet(
          boothId: boothId,
          boothName: boothName,
          boothNumber: boothNumber,
          resumes: resumes,
          matchedResumeId: matchedResumeId,
          joinToken: joinToken,
          onDone: onDone,
        ),
      ),
    );

class _DropSheet extends ConsumerStatefulWidget {
  final String boothId;
  final String boothName;
  final int boothNumber;
  final List<Json> resumes;
  final String? matchedResumeId;
  final String? joinToken;
  final Future<void> Function() onDone;
  const _DropSheet(
      {required this.boothId,
      required this.boothName,
      required this.boothNumber,
      required this.resumes,
      required this.matchedResumeId,
      required this.joinToken,
      required this.onDone});
  @override
  ConsumerState<_DropSheet> createState() => _DropSheetState();
}

class _DropSheetState extends ConsumerState<_DropSheet> {
  late String? resumeId = widget.matchedResumeId ?? (widget.resumes.isNotEmpty ? widget.resumes.first['id'] as String : null);
  final note = TextEditingController();
  String? noteJob;
  String? noteSource;
  bool sending = false;
  String? error;

  Future<void> _suggest() async {
    if (resumeId == null) return;
    final r = await ref.read(apiProvider).post('/api/booths/${widget.boothId}/note', {'resume_id': resumeId});
    setState(() => noteJob = r['job_id'] as String);
  }

  Future<void> _send() async {
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final r = await ref.read(apiProvider).post('/api/booths/${widget.boothId}/drop', {
        'resume_id': resumeId,
        'note': note.text.trim(),
        't': widget.joinToken,
      });
      if (mounted) {
        Navigator.pop(context);
        toast(context, r['message'] as String);
      }
      await widget.onDone();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 0, T.gutter, T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Drop and go: Booth ${widget.boothNumber}, ${widget.boothName}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: T.s1),
            const Text('Goes straight to the recruiter inbox. No printing.', style: TextStyle(color: T.muted)),
            const SizedBox(height: T.s3),
            RadioGroup<String>(
              groupValue: resumeId,
              onChanged: (v) => setState(() => resumeId = v),
              child: Column(children: [
                for (final r in widget.resumes)
                  RadioListTile<String>(
                    value: r['id'] as String,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r['label']} resume', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: r['id'] == widget.matchedResumeId ? const Text('Matched for this booth') : null,
                  ),
              ]),
            ),
            const SizedBox(height: T.s2),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 2,
              maxLength: 240,
              decoration: const InputDecoration(labelText: S.notePlaceholder),
            ),
            if (noteJob != null)
              JobProgress(
                jobId: noteJob!,
                compact: true,
                onDone: (j) => setState(() {
                  final res = j['result'] as Json? ?? {};
                  note.text = (res['note'] as String? ?? '').split('\n').take(2).join('\n');
                  noteSource = res['source'] == 'offline' ? 'Offline draft from your resume lines' : 'Suggested in your voice. Edit it freely.';
                  noteJob = null;
                }),
                onError: (m) => setState(() {
                  error = m;
                  noteJob = null;
                }),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _suggest, icon: const Icon(Icons.auto_awesome_outlined, size: 18), label: const Text(S.suggestNote)),
              ),
            if (noteSource != null) Text(noteSource!, style: const TextStyle(fontSize: T.tiny, color: T.muted)),
            if (error != null) ...[const SizedBox(height: T.s2), Banner2(text: error!, color: T.danger, bg: T.dangerBg)],
            const SizedBox(height: T.s3),
            FilledButton(onPressed: sending || resumeId == null ? null : _send, child: const Text(S.sendDrop)),
          ]),
        ),
      );
}
