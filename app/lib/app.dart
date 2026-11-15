import 'package:device_preview/device_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/api/api.dart';
import 'core/design/theme.dart';
import 'core/strings.dart';
import 'core/widgets/splash.dart';
import 'features/links_page.dart';
import 'features/about/about_page.dart';
import 'features/booth/student_booth_page.dart';
import 'features/game/fairplay_page.dart';
import 'features/game/recap_page.dart';
import 'features/game/receipts_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/onboarding/student_login_page.dart';
import 'features/onboarding/welcome_page.dart';
import 'features/organizer/organizer_page.dart';
import 'features/plan/home_shell.dart';
import 'features/recruiter/recruiter_shell.dart';
import 'features/plan/scan_page.dart';
import 'features/recruiter/recruiter_login_page.dart';
import 'features/recruiter/recruiter_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => const _RoleGate(),
      ),
      GoRoute(path: '/welcome', builder: (c, s) => const WelcomePage()),
      // One link per feature, for jumping straight to any screen in a demo.
      GoRoute(path: '/links', builder: (c, s) => const LinksPage()),
      for (final (i, name) in ['map', 'booths', 'quests', 'cards', 'me'].indexed)
        GoRoute(path: '/$name', builder: (c, s) => _StudentGate(child: HomeShell(key: ValueKey('s$i'), initialTab: i))),
      for (final (i, name) in ['line', 'candidates', 'cards', 'me'].indexed)
        GoRoute(path: '/r/$name', builder: (c, s) => _RecruiterGate(tab: i)),
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingPage()),
      GoRoute(path: '/login', builder: (c, s) => const StudentLoginPage()),
      GoRoute(path: '/scan', builder: (c, s) => const _StudentGate(child: ScanPage())),
      // Student booth screen (tap in plan, or demo).
      GoRoute(
        path: '/b/:id',
        builder: (c, s) => _StudentGate(child: StudentBoothPage(boothId: s.pathParameters['id']!)),
      ),
      // Booth QR code target: /join/<booth>?t=<token>. Works from the in-app
      // scanner and from the iPhone camera app.
      GoRoute(
        path: '/join/:id',
        builder: (c, s) => _StudentGate(
          child: StudentBoothPage(boothId: s.pathParameters['id']!, joinToken: s.uri.queryParameters['t']),
        ),
      ),
      // Recruiter booth view: no login, the key in the link is the credential.
      GoRoute(
        path: '/booth/:id',
        builder: (c, s) => RecruiterPage(boothId: s.pathParameters['id']!, keyParam: s.uri.queryParameters['key']),
      ),
      GoRoute(path: '/recruiter', builder: (c, s) => const RecruiterLoginPage()),
      GoRoute(path: '/organizer', builder: (c, s) => OrganizerPage(keyParam: s.uri.queryParameters['org'])),
      GoRoute(path: '/recap', builder: (c, s) => const _StudentGate(child: RecapPage())),
      GoRoute(path: '/fairplay', builder: (c, s) => const _StudentGate(child: FairPlayPage())),
      GoRoute(path: '/why', builder: (c, s) => const _StudentGate(child: ReceiptsPage())),
      GoRoute(path: '/about', builder: (c, s) => const AboutPage()),
    ],
  );
});

/// "/" shows the student app, the recruiter app, or the role choice.
class _RoleGate extends ConsumerWidget {
  const _RoleGate();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(recruiterProvider);
    if (rec != null) return RecruiterShell(auth: rec);
    if (ref.watch(sessionProvider) != null) return const HomeShell();
    return const WelcomePage();
  }
}

/// Recruiter pages need a recruiter session; without one, show sign-in.
class _RecruiterGate extends ConsumerWidget {
  final int tab;
  const _RecruiterGate({required this.tab});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(recruiterProvider);
    if (rec == null) return const RecruiterLoginPage();
    return RecruiterShell(key: ValueKey('r$tab'), auth: rec, initialTab: tab);
  }
}

/// Student pages need a session; without one, show the welcome screen.
class _StudentGate extends ConsumerWidget {
  final Widget child;
  const _StudentGate({required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(sessionProvider);
    if (token == null) return const WelcomePage();
    return child;
  }
}

class QueueCueApp extends ConsumerStatefulWidget {
  final bool framed;
  final bool splash;
  const QueueCueApp({super.key, this.framed = false, this.splash = true});
  @override
  ConsumerState<QueueCueApp> createState() => _QueueCueAppState();
}

class _QueueCueAppState extends ConsumerState<QueueCueApp> {
  late bool showSplash = widget.splash;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: S.app,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: ref.watch(routerProvider),
        locale: widget.framed ? DevicePreview.locale(context) : null,
        builder: (context, child) {
          Widget w = Stack(children: [
            child ?? const SizedBox(),
            if (showSplash) Positioned.fill(child: SplashOverlay(onDone: () => setState(() => showSplash = false))),
          ]);
          if (widget.framed) w = DevicePreview.appBuilder(context, w);
          return w;
        },
      );
}
