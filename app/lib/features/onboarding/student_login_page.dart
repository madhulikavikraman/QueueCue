import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';

/// Students sign back in to their saved account (and their half-finished setup).
class StudentLoginPage extends ConsumerStatefulWidget {
  const StudentLoginPage({super.key});
  @override
  ConsumerState<StudentLoginPage> createState() => _StudentLoginPageState();
}

class _StudentLoginPageState extends ConsumerState<StudentLoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await ref.read(apiProvider).post('/api/students/login', {'email': email.text, 'password': pass.text});
      await ref.read(recruiterProvider.notifier).set(null);
      await ref.read(sessionProvider.notifier).set(r['token'] as String);
      if (mounted) context.go(r['onboarded'] == true ? '/' : '/onboarding');
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: const BackOrHome(), title: const Text('Student sign-in')),
        body: PageBody(maxWidth: 520, children: [
          const Text('Sign in with the email and password you set up. You go straight back to where you left off.',
              style: TextStyle(color: T.muted)),
          const SizedBox(height: T.s4),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: T.s3),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), onSubmitted: (_) => _login()),
          if (error != null) ...[const SizedBox(height: T.s3), Banner2(text: error!, color: T.danger, bg: T.dangerBg)],
          const SizedBox(height: T.s4),
          FilledButton(onPressed: busy ? null : _login, child: const Text('Sign in')),
          const SizedBox(height: T.s2),
          TextButton(onPressed: () => context.go('/onboarding'), child: const Text('New here? Set up in 2 minutes')),
          const Text('Forgot your password? The organizer help desk can give you a temporary one.',
              style: TextStyle(color: T.muted, fontSize: T.small)),
          const SizedBox(height: T.s3),
          const Text('Demo students: viktor.krum@example.edu, hermione.granger@example.edu, percy.weasley@example.edu (password: hogwarts)',
              style: TextStyle(color: T.muted, fontSize: T.small)),
        ]),
      );
}
