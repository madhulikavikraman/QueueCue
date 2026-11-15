import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';

/// Edit the recruiter's card + booth details, or their sign-in credentials.
Future<void> showRecruiterEdit(BuildContext context, WidgetRef ref, RecruiterAuth auth, {bool credentials = false}) async {
  final api = ref.read(apiProvider);
  final q = 'key=${Uri.encodeComponent(auth.key)}';
  Json view;
  try {
    view = await api.get('/api/recruiter/${auth.boothId}?$q');
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return;
  }
  final b = view['booth'] as Json;
  final card = ((await api.get('/api/recruiter/${auth.boothId}/cards?$q'))['me']) as Json;
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _EditSheet(auth: auth, booth: b, card: card, credentials: credentials),
    ),
  );
}

class _EditSheet extends ConsumerStatefulWidget {
  final RecruiterAuth auth;
  final Json booth;
  final Json card;
  final bool credentials;
  const _EditSheet({required this.auth, required this.booth, required this.card, required this.credentials});
  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late final name = TextEditingController(text: '${widget.card['name'] ?? ''}');
  late final title = TextEditingController(text: '${widget.card['title'] ?? ''}');
  late final company = TextEditingController(text: '${widget.booth['name'] ?? ''}');
  late final role = TextEditingController(
      text: '${(((widget.booth['roles'] as List?) ?? []).cast<Map>().firstOrNull)?['title'] ?? ''}');
  late final about = TextEditingController(text: '${widget.booth['about'] ?? ''}');
  late String sponsors = '${widget.booth['sponsors'] ?? 'unknown'}';
  late final email = TextEditingController(text: '${widget.card['email'] ?? ''}');
  late final cardEmail = TextEditingController(text: '${widget.card['email'] ?? ''}');
  final current = TextEditingController();
  final newPass = TextEditingController();
  String? error;
  bool saving = false;

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final body = widget.credentials
          ? {'email': email.text.trim(), 'new_password': newPass.text, 'current_password': current.text}
          : {
              'name': name.text.trim(),
              'title': title.text.trim(),
              'company': company.text.trim(),
              'role': role.text.trim(),
              'about': about.text.trim(),
              'sponsors': sponsors,
              'card_email': cardEmail.text.trim(),
            };
      final r = await ref.read(apiProvider).post('/api/recruiter/${widget.auth.boothId}/profile?key=${Uri.encodeComponent(widget.auth.key)}', body);
      final c = r['card'] as Json;
      await ref.read(recruiterProvider.notifier).set(
          (boothId: widget.auth.boothId, key: widget.auth.key, name: '${c['name']}', company: '${c['company']}'));
      if (mounted) {
        Navigator.pop(context);
        toast(context, r['message'] as String);
      }
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 0, T.gutter, T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.credentials ? 'Sign-in email and password' : 'My card and booth', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: T.s3),
            if (widget.credentials) ...[
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Sign-in email')),
              const SizedBox(height: T.s3),
              TextField(controller: newPass, obscureText: true, decoration: const InputDecoration(labelText: 'New password (leave blank to keep it)')),
              const SizedBox(height: T.s3),
              TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password (required)')),
            ] else ...[
              TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: T.s3),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: T.s3),
              TextField(
                controller: cardEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email on card (what students see)', helperText: 'Your sign-in email stays the same; change it under Me.'),
              ),
              const SizedBox(height: T.s3),
              TextField(controller: company, decoration: const InputDecoration(labelText: 'Company')),
              const SizedBox(height: T.s3),
              TextField(controller: role, decoration: const InputDecoration(labelText: 'Role you are hiring for')),
              const SizedBox(height: T.s3),
              TextField(controller: about, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'What the role does (students see this)')),
              const SizedBox(height: T.s3),
              const Text('Sponsors visas?', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: T.s2),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'yes', label: Text('Yes')),
                  ButtonSegment(value: 'no', label: Text('No')),
                  ButtonSegment(value: 'unknown', label: Text('Not sure')),
                ],
                selected: {sponsors},
                onSelectionChanged: (s) => setState(() => sponsors = s.first),
              ),
            ],
            if (error != null) ...[const SizedBox(height: T.s3), Banner2(text: error!, color: T.danger, bg: T.dangerBg)],
            const SizedBox(height: T.s4),
            FilledButton(onPressed: saving ? null : _save, child: const Text('Save')),
          ]),
        ),
      );
}
