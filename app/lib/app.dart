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
import 'features/game/showcase_page.dart';
import 'features/game/receipts_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/onboarding/student_login_page.dart';
import 'features/onboarding/welcome_page.dart';
import 'features/organizer/organizer_page.dart';
import 'features/game/me_tab.dart';
import 'features/plan/home_shell.dart';
import 'features/plan/map_tab.dart';
import 'features/plan/plan_tab.dart';
import 'features/plan/qr_tab.dart';
import 'features/recruiter/recruiter_shell.dart';
import 'features/recruiter/recruiter_login_page.dart';
import 'features/recruiter/recruiter_page.dart';

/// Re-runs the router's redirect when someone signs in or out.
class _AuthRefresh extends ChangeNotifier {
  void bump() => notifyListeners();
}

const _studentOnly = ['/map', '/booths', '/quests', '/cards', '/me', '/b/', '/join/', '/recap', '/fairplay', '/why'];

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh();
  ref.listen(sessionProvider, (_, __) => refresh.bump());
  ref.listen(recruiterProvider, (_, __) => refresh.bump());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    // One rule for where each role belongs. Every screen keeps its own URL,
    // so the browser Back button and refresh both work.
    redirect: (context, state) {
      final path = state.uri.path;
      final rec = ref.read(recruiterProvider);
      final student = ref.read(sessionProvider);
      if (path == '/') return rec != null ? '/r/line' : (student != null ? '/map' : '/welcome');
      if (student == null && _studentOnly.any((p) => path == p || (p.endsWith('/') && path.startsWith(p)))) return '/welcome';
      if (rec == null && path.startsWith('/r/')) return '/recruiter';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (c, s) => const WelcomePage()),
      GoRoute(path: '/welcome', builder: (c, s) => const WelcomePage()),
      GoRoute(path: '/links', builder: (c, s) => const LinksPage()),
      GoRoute(path: '/showcase', builder: (c, s) => const ShowcasePage()),
      // Student app: each tab keeps its own state and URL.
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (c, s) => const MapTab())]),
          StatefulShellBranch(routes: [GoRoute(path: '/booths', builder: (c, s) => const PlanTab())]),
          StatefulShellBranch(routes: [GoRoute(path: '/quests', builder: (c, s) => const MeTab(game: true))]),
          StatefulShellBranch(routes: [GoRoute(path: '/cards', builder: (c, s) => const CardTab())]),
          StatefulShellBranch(routes: [GoRoute(path: '/me', builder: (c, s) => const MeTab())]),
        ],
      ),
      // Recruiter app.
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => RecruiterShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/r/line', builder: (c, s) => const RecruiterTab(mode: 'line'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/r/candidates', builder: (c, s) => const RecruiterTab(mode: 'list'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/r/cards', builder: (c, s) => const RecruiterTab(mode: 'cards'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/r/me', builder: (c, s) => const RecruiterTab(mode: 'me'))]),
        ],
      ),
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingPage()),
      GoRoute(path: '/login', builder: (c, s) => const StudentLoginPage()),
      GoRoute(path: '/b/:id', builder: (c, s) => StudentBoothPage(boothId: s.pathParameters['id']!)),
      GoRoute(
        path: '/join/:id',
        builder: (c, s) => StudentBoothPage(boothId: s.pathParameters['id']!, joinToken: s.uri.queryParameters['t']),
      ),
      // Big-screen booth view: the key in the link is the credential.
      GoRoute(
        path: '/booth/:id',
        builder: (c, s) => RecruiterPage(boothId: s.pathParameters['id']!, keyParam: s.uri.queryParameters['key']),
      ),
      GoRoute(path: '/recruiter', builder: (c, s) => const RecruiterLoginPage()),
      GoRoute(path: '/organizer', builder: (c, s) => OrganizerPage(keyParam: s.uri.queryParameters['org'])),
      GoRoute(path: '/recap', builder: (c, s) => const RecapPage()),
      GoRoute(path: '/fairplay', builder: (c, s) => const FairPlayPage()),
      GoRoute(path: '/why', builder: (c, s) => const ReceiptsPage()),
      GoRoute(path: '/about', builder: (c, s) => const AboutPage()),
    ],
    errorBuilder: (c, s) => const WelcomePage(),
  );
});

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
