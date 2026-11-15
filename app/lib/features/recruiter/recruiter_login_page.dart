import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../onboarding/onboarding_page.dart' show majors;

/// Recruiter sign-in, sign-up (with the fair code), and remembered accounts.
class RecruiterLoginPage extends ConsumerStatefulWidget {
  const RecruiterLoginPage({super.key});
  @override
  ConsumerState<RecruiterLoginPage> createState() => _RecruiterLoginPageState();
}

class _RecruiterLoginPageState extends ConsumerState<RecruiterLoginPage> {
  static const _recentKey = 'qq_recent_recruiters';
  int tab = 0; // 0 sign in, 1 sign up
  final email = TextEditingController();
  final pass = TextEditingController();
  final code = TextEditingController();
  final name = TextEditingController();
  final suEmail = TextEditingController();
  final suPass = TextEditingController();
  final company = TextEditingController();
  final title = TextEditingController(text: 'Campus recruiter');
  final role = TextEditingController();
  final about = TextEditingController();
  String sponsors = 'unknown';
  bool citizensOnly = false;
  final Set<String> hires = {'Computer Science', 'Computer Engineering', 'Electrical Engineering', 'Data Science'};

  String? error;
  Json? demo;
  bool busy = false;
  List<Json> recent = [];

  Api get api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    api.get('/api/demo/personas').then((d) {
      if (mounted) setState(() => demo = d);
    }).catchError((_) {});
    Prefs.get(_recentKey).then((v) {
      if (v == null || v.isEmpty || !mounted) return;
      try {
        setState(() => recent = (jsonDecode(v) as List).cast<Json>());
      } catch (_) {}
    });
  }

  /// Remember this account on this device and open the recruiter app.
  Future<void> _enter(Json r) async {
    final a = (boothId: r['booth_id'] as String, key: r['key'] as String, name: '${r['name'] ?? ''}', company: '${r['company'] ?? ''}');
    final list = [
      {'booth_id': a.boothId, 'key': a.key, 'name': a.name, 'company': a.company},
      ...recent.where((x) => x['booth_id'] != a.boothId),
    ].take(5).toList();
    await Prefs.set(_recentKey, jsonEncode(list));
    await Prefs.set('qq_booth_key_${a.boothId}', a.key);
    await ref.read(recruiterProvider.notifier).set(a);
    if (mounted) context.go('/');
  }

  Future<void> _forget(Json r) async {
    final list = recent.where((x) => x['booth_id'] != r['booth_id']).toList();
    await Prefs.set(_recentKey, jsonEncode(list));
    setState(() => recent = list);
  }

  Future<void> _run(Future<Json> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await f();
      if (!mounted) return;
      if (r['resumed'] == true) {
        toast(context, 'You already had an account. Signed you in.');
      } else if (r['tent'] != null) {
        toast(context, 'Welcome. Your booth is Tent ${r['tent']}; your card number is ${r['number']}.');
      }
      await _enter(r);
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Json> _signIn() => api.post('/api/recruiter/login', {'email': email.text, 'password': pass.text});

  Future<Json> _signUp() => api.post('/api/recruiter/signup', {
        'code': code.text,
        'name': name.text,
        'email': suEmail.text,
        'password': suPass.text,
        'company': company.text,
        'title': title.text,
        'role': role.text,
        'about': about.text,
        'sponsors': sponsors,
        'citizenship_required': citizensOnly,
        'majors': hires.toList(),
        'skills': about.text.toLowerCase().split(RegExp(r'[,;/]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      });

  @override
  Widget build(BuildContext context) {
    final links = ((demo?['booth_links'] as List?) ?? []).cast<Json>();
    return Scaffold(
      appBar: AppBar(leading: const BackOrHome(), title: const Text('Recruiters')),
      body: PageBody(maxWidth: 560, children: [
        if (recent.isNotEmpty) ...[
          const Text('On this device', style: TextStyle(fontWeight: FontWeight.w800, fontSize: T.h3)),
          const SizedBox(height: T.s2),
          for (final r in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: T.s2),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined, color: T.brand),
                  title: Text('Continue as ${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${r['company']}'),
                  trailing: IconButton(tooltip: 'Forget on this device', icon: const Icon(Icons.close), onPressed: () => _forget(r)),
                  onTap: () => _enter(r),
                ),
              ),
            ),
          const SizedBox(height: T.s3),
        ],
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Sign in'), icon: Icon(Icons.login)),
            ButtonSegment(value: 1, label: Text('Sign up'), icon: Icon(Icons.person_add_alt)),
          ],
          selected: {tab},
          onSelectionChanged: (s) => setState(() {
            tab = s.first;
            error = null;
          }),
        ),
        const SizedBox(height: T.s4),
        if (tab == 0) ...[
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email')),
          const SizedBox(height: T.s3),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), onSubmitted: (_) => _run(_signIn)),
        ] else ...[
          const Text('Use the fair code the organizer emailed you.', style: TextStyle(color: T.muted)),
          const SizedBox(height: T.s3),
          TextField(
            controller: code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Fair code', hintText: 'TROJANCAREERFAIR'),
          ),
          const SizedBox(height: T.s3),
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name')),
          const SizedBox(height: T.s3),
          TextField(controller: suEmail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email')),
          const SizedBox(height: T.s3),
          TextField(controller: suPass, obscureText: true, decoration: const InputDecoration(labelText: 'Password (4+ characters)')),
          const SizedBox(height: T.s3),
          TextField(controller: company, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Company')),
          const SizedBox(height: T.s3),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Your title')),
          const SizedBox(height: T.s3),
          TextField(controller: role, decoration: const InputDecoration(labelText: 'Role you are hiring for', hintText: 'Software Engineer Intern')),
          const SizedBox(height: T.s3),
          TextField(
            controller: about,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'What the role does (students see this; it drives fit scores)', hintText: 'python, backend APIs, on-call'),
          ),
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('US citizens only'),
            value: citizensOnly,
            onChanged: (v) => setState(() => citizensOnly = v),
          ),
          const Text('Majors you hire', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: T.s2),
          Wrap(spacing: T.s2, runSpacing: T.s2, children: [
            for (final m in majors)
              FilterChip(label: Text(m), selected: hires.contains(m), onSelected: (v) => setState(() => v ? hires.add(m) : hires.remove(m))),
          ]),
        ],
        if (error != null) ...[const SizedBox(height: T.s3), Banner2(text: error!, color: T.danger, bg: T.dangerBg)],
        const SizedBox(height: T.s4),
        FilledButton(
          onPressed: busy ? null : () => _run(tab == 0 ? _signIn : _signUp),
          child: Text(tab == 0 ? 'Sign in' : 'Create my booth'),
        ),
        if (links.isNotEmpty && tab == 0) ...[
          const SectionTitle('Demo Mode: sign in as a booth',
              sub: 'Seeded accounts use the company short name as the password, e.g. kingsley@northwind.example / northwind'),
          for (final b in links)
            ListTile(
              dense: true,
              title: Text('${b['number']}. ${b['name']}'),
              subtitle: b['recruiter'] != null ? Text('${b['recruiter']}') : null,
              trailing: const Icon(Icons.login, size: 18),
              onTap: () => _enter({'booth_id': b['id'], 'key': b['key'], 'name': b['recruiter'], 'company': b['name']}),
            ),
        ],
      ]),
    );
  }
}
