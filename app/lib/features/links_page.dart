import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api.dart';
import '../core/design/tokens.dart';
import '../core/widgets/common.dart';

/// Every feature on one page, for jumping straight to any screen in a demo.
class LinksPage extends ConsumerWidget {
  const LinksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(sessionProvider);
    final rec = ref.watch(recruiterProvider);

    Future<void> asStudent(String token) async {
      await ref.read(recruiterProvider.notifier).set(null);
      await ref.read(sessionProvider.notifier).set(token);
    }

    Future<void> asRecruiter(String boothId, String name, String company) async {
      await ref.read(recruiterProvider.notifier).set((boothId: boothId, key: 'bk-$boothId', name: name, company: company));
    }

    Widget link(String path, String title, String sub, IconData icon) => ListTile(
          leading: Icon(icon, color: T.brand),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$sub\n$path', style: const TextStyle(fontSize: T.small)),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(path),
        );

    return Scaffold(
      appBar: AppBar(leading: const BackOrHome(), title: const Text('All screens')),
      body: PageBody(children: [
        const Text('Jump straight to any feature. Each one is also a URL you can bookmark or open on another device.',
            style: TextStyle(color: T.muted)),
        const SectionTitle('Signed in as'),
        Wrap(spacing: T.s2, runSpacing: T.s2, children: [
          Pill(student == null ? 'No student' : 'Student: $student', icon: Icons.school_outlined),
          Pill(rec == null ? 'No recruiter' : 'Recruiter: ${rec.name} (${rec.company})', icon: Icons.badge_outlined),
        ]),
        const SizedBox(height: T.s3),
        Wrap(spacing: T.s2, runSpacing: T.s2, children: [
          OutlinedButton(onPressed: () => asStudent('demo-viktor'), child: const Text('Be Viktor')),
          OutlinedButton(onPressed: () => asStudent('demo-hermione'), child: const Text('Be Hermione')),
          OutlinedButton(onPressed: () => asStudent('demo-percy'), child: const Text('Be Percy')),
          OutlinedButton(
              onPressed: () => asRecruiter('northwind', 'Kingsley Shacklebolt', 'Northwind Cloud'), child: const Text('Be Kingsley (recruiter)')),
        ]),
        const SectionTitle('Start'),
        Card(
          child: Column(children: [
            link('/welcome', 'Welcome', 'Pick student or recruiter', Icons.waving_hand_outlined),
            link('/onboarding', 'Student sign-up', 'Profile, resumes, voice, plan', Icons.app_registration),
            link('/recruiter', 'Recruiter sign-in', 'Email and password', Icons.login),
            link('/about', 'About', 'The problem and the fairness rules', Icons.info_outline),
          ]),
        ),
        const SectionTitle('Student app'),
        Card(
          child: Column(children: [
            link('/map', 'Map', 'Tents in a line and your route', Icons.map_outlined),
            link('/booths', 'Booths', 'Every booth ranked by fit', Icons.storefront_outlined),
            link('/b/northwind', 'One booth', 'Wait time, join line, drop resume, pitch', Icons.store_outlined),
            link('/quests', 'Quests', 'Level, side quests, badges, leaderboard', Icons.emoji_events_outlined),
            link('/cards', 'Cards', 'My card, swap by number, rolodex', Icons.badge_outlined),
            link('/me', 'Me', 'Profile, resumes, help, sign out', Icons.person_outline),
            link('/recap', 'Fair Recap', 'End-of-day summary', Icons.summarize_outlined),
            link('/fairplay', 'Fair Play matches', 'Top 3 fits get your resume at close', Icons.verified_outlined),
            link('/why', 'Why am I here?', 'Fairness receipts', Icons.balance_outlined),
          ]),
        ),
        const SectionTitle('Recruiter app'),
        Card(
          child: Column(children: [
            link('/r/line', 'Line', 'Queue, card requests, Met, enter number', Icons.people_alt_outlined),
            link('/r/candidates', 'Candidates', 'Shortlist in three sections, filters, exports', Icons.format_list_numbered),
            link('/r/cards', 'Cards', 'My card, swaps, rolodex of students and recruiters', Icons.badge_outlined),
            link('/r/me', 'Me', 'Top-rated download, close line, sign out', Icons.person_outline),
            link('/booth/northwind?key=bk-northwind', 'Big-screen booth view', 'Line and shortlist side by side (laptop)', Icons.laptop_mac),
          ]),
        ),
        const SectionTitle('Organizer'),
        Card(
          child: Column(children: [
            link('/organizer?org=org-demo-key', 'Organizer', 'Heat map, close fair, audit, help requests', Icons.map),
          ]),
        ),
      ]),
    );
  }
}
