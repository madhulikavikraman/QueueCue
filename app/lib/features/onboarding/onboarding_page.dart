import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/platform/recorder.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';

const majors = [
  'Computer Science',
  'Computer Engineering',
  'Electrical Engineering',
  'Data Science',
  'Business Analytics',
  'Mathematics',
  'Statistics',
  'Mechanical Engineering',
  'Aerospace Engineering',
  'Industrial & Systems Engineering',
  'Biomedical Engineering',
  'Finance',
  'Economics',
  'Interactive Media',
];
const avatarNames = ['fox', 'owl', 'bear', 'cat', 'frog', 'panda', 'koala', 'tiger', 'otter', 'bunny'];

/// Onboarding, target 2 minutes: profile -> resumes -> voice -> plan.
/// If the session already exists (e.g. editing later), it resumes at resumes.
class OnboardingPage extends ConsumerStatefulWidget {
  final int startStep;
  const OnboardingPage({super.key, this.startStep = 0});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  late int step = widget.startStep;
  // profile
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final interests = TextEditingController();
  final bio = TextEditingController();
  String? major;
  String degree = 'BS';
  int gradYear = DateTime.now().year + 1;
  String? auth;
  String avatar = 'fox';
  // resumes
  List<Json> resumes = [];
  bool busy = false;
  String? error;
  // voice
  final transcript = TextEditingController();
  final a1 = TextEditingController();
  final a2 = TextEditingController();
  bool typing = false;
  String? voiceJob;
  String? wavB64;
  int wavSecs = 0;
  // build
  String? buildJob;

  Api get api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    if (ref.read(sessionProvider) != null && step == 0) {
      step = 1;
      _resume();
    }
  }

  /// Continue a half-finished setup at the step where it stopped.
  Future<void> _resume() async {
    try {
      final me = await api.get('/api/me');
      final rs = ((me['resumes'] as List?) ?? []).cast<Json>();
      setState(() => resumes = rs);
      if (rs.isEmpty) {
        setState(() => step = 1);
      } else if (me['has_voice'] != true && me['voice_skipped'] != true) {
        setState(() => step = 2);
      } else if (me['onboarded'] != true) {
        await _startBuild();
      } else if (widget.startStep == 0 && mounted) {
        context.go('/');
      }
    } catch (_) {}
  }

  Future<void> _refreshResumes() async {
    try {
      final me = await api.get('/api/me');
      setState(() => resumes = ((me['resumes'] as List?) ?? []).cast<Json>());
    } catch (_) {}
  }

  Future<void> _createProfile() async {
    if (name.text.trim().isEmpty || major == null || auth == null || email.text.trim().isEmpty || password.text.length < 4) {
      setState(() => error = 'Name, email, a password (4+ characters), major and work authorization are needed. '
          'Email and password let you come back to this account.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await api.post('/api/students', {
        'name': name.text.trim(),
        'email': email.text.trim(),
        'password': password.text,
        'major': major,
        'degree': degree,
        'grad_year': gradYear,
        'work_auth': auth,
        'avatar': avatar,
        'interests': interests.text.trim(),
        'bio': bio.text.trim(),
      });
      await ref.read(recruiterProvider.notifier).set(null);
      await ref.read(sessionProvider.notifier).set(r['token'] as String);
      if (r['resumed'] == true) {
        if (mounted) toast(context, 'Welcome back. Picking up where you left off.');
        setState(() => step = 1);
        await _resume();
      } else {
        setState(() => step = 1);
      }
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _addResume({bool paste = false}) async {
    final label = await _ask('Label this resume', S.resumeLabelHint);
    if (label == null || label.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (paste) {
        final text = await _ask('Paste your resume text', 'Paste the full text', multiline: true);
        if (text == null) return;
        await api.post('/api/me/resumes', {'label': label.trim(), 'text': text});
      } else {
        final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
        if (files.isEmpty) return;
        final f = files.first;
        final bytes = await f.readAsBytes();
        try {
          await api.post('/api/me/resumes', {'label': label.trim(), 'filename': f.name, 'pdf_base64': base64Encode(bytes)});
        } on ApiException catch (e) {
          if (e.data['needs_text'] == true) {
            final text = await _ask('We could not read that PDF. Paste the text instead.', 'Paste the full text', multiline: true);
            if (text == null) return;
            await api.post('/api/me/resumes', {'label': label.trim(), 'text': text});
          } else {
            rethrow;
          }
        }
      }
      await _refreshResumes();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _ask(String title, String hint, {bool multiline = false}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: c,
            autofocus: true,
            minLines: multiline ? 6 : 1,
            maxLines: multiline ? 12 : 1,
            decoration: InputDecoration(hintText: hint),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _submitVoice() async {
    final answers = [if (a1.text.trim().isNotEmpty) '${S.voiceQ1} ${a1.text.trim()}', if (a2.text.trim().isNotEmpty) '${S.voiceQ2} ${a2.text.trim()}'];
    if (wavB64 == null && transcript.text.trim().length < 20) {
      setState(() => error = 'Record 20 to 30 seconds, or type your answer.');
      return;
    }
    setState(() => error = null);
    try {
      final r = await api.post('/api/me/voice', {
        if (wavB64 != null) 'wav_base64': wavB64,
        if (wavB64 == null) 'transcript': transcript.text.trim(),
        'answers': answers,
      });
      setState(() => voiceJob = r['job_id'] as String);
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _startBuild() async {
    try {
      final r = await api.post('/api/me/onboard');
      setState(() {
        step = 3;
        buildJob = r['job_id'] as String;
      });
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [S.stepProfile, S.stepResumes, S.stepVoice, S.stepBuilding];
    return Scaffold(
      appBar: AppBar(
        title: Text('${step + 1} of 4 · ${titles[step]}'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/'), tooltip: 'Close'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (step + 1) / 4, minHeight: 4),
        ),
      ),
      body: PageBody(children: [
        if (error != null) ...[Banner2(text: error!, color: T.danger, bg: T.dangerBg, icon: Icons.error_outline), const SizedBox(height: T.s3)],
        ...switch (step) { 0 => _profile(), 1 => _resumes(), 2 => _voice(), _ => _building() },
      ]),
      bottomNavigationBar: _bottom(),
    );
  }

  Widget? _bottom() {
    switch (step) {
      case 0:
        return BottomAction(child: FilledButton(onPressed: busy ? null : _createProfile, child: const Text('Continue')));
      case 1:
        return BottomAction(
          child: FilledButton(onPressed: resumes.isEmpty || busy ? null : () => setState(() => step = 2), child: const Text('Continue')),
          above: resumes.length == 1 ? const Text('Tip: a second, differently focused resume lets QueueCue match booths better.', style: TextStyle(color: T.muted, fontSize: T.small)) : null,
        );
      case 2:
        if (voiceJob != null) return null;
        return BottomAction(
          child: FilledButton(onPressed: _submitVoice, child: const Text('Save my voice')),
          secondary: TextButton(
            onPressed: () async {
              await api.post('/api/me/voice/skip');
              await _startBuild();
            },
            child: const Text(S.skipVoice),
          ),
          above: const Text(S.skipVoiceNote, style: TextStyle(color: T.muted, fontSize: T.small)),
        );
    }
    return null;
  }

  List<Widget> _profile() => [
        TextField(controller: name, decoration: const InputDecoration(labelText: S.nameLabel), textCapitalization: TextCapitalization.words),
        const SizedBox(height: T.s3),
        DropdownButtonFormField<String>(
          initialValue: major,
          isExpanded: true,
          decoration: const InputDecoration(labelText: S.majorLabel),
          items: [for (final m in majors) DropdownMenuItem(value: m, child: Text(m))],
          onChanged: (v) => setState(() => major = v),
        ),
        const SizedBox(height: T.s3),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: degree,
              decoration: const InputDecoration(labelText: S.degreeLabel),
              items: [for (final d in ['BS', 'BA', 'MS', 'MBA', 'PhD']) DropdownMenuItem(value: d, child: Text(d))],
              onChanged: (v) => setState(() => degree = v ?? 'BS'),
            ),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: gradYear,
              decoration: const InputDecoration(labelText: S.gradYearLabel),
              items: [for (var y = DateTime.now().year; y <= DateTime.now().year + 5; y++) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) => setState(() => gradYear = v ?? gradYear),
            ),
          ),
        ]),
        const SizedBox(height: T.s3),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (you sign back in with this)')),
        const SizedBox(height: T.s3),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (4+ characters)')),
        const SizedBox(height: T.s2),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => context.go('/login'), child: const Text('Already started? Sign in to continue')),
        ),
        const SizedBox(height: T.s3),
        TextField(controller: interests, decoration: const InputDecoration(labelText: 'Interests (for your business card)', hintText: 'robotics, LLMs, chess')),
        const SizedBox(height: T.s3),
        TextField(controller: bio, maxLength: 160, decoration: const InputDecoration(labelText: 'One line about you (for your business card)')),
        SectionTitle(S.workAuthLabel, sub: S.workAuthWhy),
        RadioGroup<String>(
          groupValue: auth,
          onChanged: (v) => setState(() => auth = v),
          child: Column(children: [
            for (final e in S.workAuth.entries)
              RadioListTile<String>(value: e.key, title: Text(e.value), contentPadding: EdgeInsets.zero),
          ]),
        ),
        const SectionTitle(S.avatarLabel),
        Wrap(spacing: T.s2, runSpacing: T.s2, children: [
          for (final a in avatarNames)
            InkWell(
              onTap: () => setState(() => avatar = a),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  border: Border.all(color: avatar == a ? T.brand : Colors.transparent, width: 2.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: PixelAvatar(a, size: 44),
              ),
            ),
        ]),
      ];

  List<Widget> _resumes() => [
        const Text(S.resumesIntro, style: TextStyle(color: T.muted)),
        const SizedBox(height: T.s4),
        if (resumes.isEmpty) const EmptyState(icon: Icons.description_outlined, title: 'No resumes yet', body: 'PDFs are read on the host laptop. Nothing leaves it.'),
        for (final r in resumes)
          Padding(
            padding: const EdgeInsets.only(bottom: T.s2),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(r['label'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${r['filename'] ?? 'Pasted text'} · ${r['chars']} characters read${r['is_default'] == true ? ' · default' : ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () async {
                    await api.delete('/api/me/resumes/${r['id']}');
                    await _refreshResumes();
                  },
                ),
              ),
            ),
          ),
        const SizedBox(height: T.s2),
        if (busy) const LoadingState(label: 'Reading your PDF on the host laptop'),
        if (!busy && resumes.length < 4)
          Wrap(spacing: T.s2, runSpacing: T.s2, children: [
            OutlinedButton.icon(onPressed: () => _addResume(), icon: const Icon(Icons.upload_file), label: const Text(S.addPdf)),
            TextButton(onPressed: () => _addResume(paste: true), child: const Text(S.pasteText)),
          ]),
      ];

  List<Widget> _voice() {
    if (voiceJob != null) {
      return [
        const SizedBox(height: T.s5),
        JobProgress(
          jobId: voiceJob!,
          onDone: (_) => _startBuild(),
          onError: (m) => setState(() {
            error = m;
            voiceJob = null;
            typing = true;
          }),
        ),
      ];
    }
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('"${S.voicePrompt}"', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: T.s2),
            const Text(S.voiceWhy, style: TextStyle(color: T.muted, fontSize: T.small)),
            const SizedBox(height: T.s4),
            if (!typing) ...[
              VoiceRecorder(
                maxSeconds: 30,
                startLabel: wavB64 == null ? 'Record (up to 30 s)' : 'Record again',
                onDone: (b64, s) => setState(() {
                  wavB64 = b64;
                  wavSecs = s;
                }),
                onError: (m) => setState(() {
                  error = m;
                  typing = true;
                }),
              ),
              if (wavB64 != null) ...[
                const SizedBox(height: T.s2),
                Text('Recorded $wavSecs seconds.${wavSecs < 15 ? ' A little longer helps: aim for 20 to 30.' : ''}', style: const TextStyle(color: T.success)),
              ],
              TextButton(onPressed: () => setState(() => typing = true), child: const Text(S.typeInstead)),
            ] else
              TextField(
                controller: transcript,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Write it the way you would say it. Contractions, your words, your order.'),
              ),
          ]),
        ),
      ),
      const SizedBox(height: T.s4),
      TextField(controller: a1, decoration: const InputDecoration(labelText: S.voiceQ1)),
      const SizedBox(height: T.s3),
      TextField(controller: a2, decoration: const InputDecoration(labelText: S.voiceQ2)),
    ];
  }

  List<Widget> _building() => [
        const SizedBox(height: T.s5),
        const Text('Scoring every booth against your resumes. Identity details are removed before scoring.', style: TextStyle(color: T.muted)),
        const SizedBox(height: T.s4),
        if (buildJob != null)
          JobProgress(
            jobId: buildJob!,
            onDone: (_) async {
              final pending = await Prefs.get('qq_pending');
              await Prefs.set('qq_pending', '');
              if (mounted) context.go(pending != null && pending.isNotEmpty ? pending : '/');
            },
            onError: (m) => setState(() => error = m),
          ),
        const SizedBox(height: T.s5),
        OutlinedButton(onPressed: () => context.go('/'), child: const Text('Go to my plan now (it fills in as scores arrive)')),
      ];
}
