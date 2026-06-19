// App shell — MaterialApp.router wired to go_router with auth redirect.
//
// Public routes: /sign-in, /sign-up, /forgot-password
// Authenticated routes live under the StatefulShellRoute at /home/* so each
// tab keeps its own back stack. Onboarding remains outside the shell at
// /onboarding (it replaces the shell during the wizard).
//
// Redirect logic:
//   - Unauthenticated visiting a non-public route → /sign-in
//   - Authenticated visiting a public auth route → /home

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/atlas/chat_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/sign_up_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/report/recent_reports_screen.dart';
import 'features/report/report_detail_screen.dart';
import 'features/tab_shell.dart';
import 'theme/theme_data.dart';

class ConcordApp extends ConsumerStatefulWidget {
  const ConcordApp({super.key});

  @override
  ConsumerState<ConcordApp> createState() => _ConcordAppState();
}

class _ConcordAppState extends ConsumerState<ConcordApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(ref);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Concord',
      debugShowCheckedModeBanner: false,
      theme: buildConcordTheme(),
      routerConfig: _router,
    );
  }
}

const _publicRoutes = <String>{
  '/sign-in',
  '/sign-up',
  '/forgot-password',
};

GoRouter _buildRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/sign-in',
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth.isLoading || !auth.hasValue) return null;

      final session = auth.requireValue;
      final loc = state.uri.path;
      final isPublic = _publicRoutes.contains(loc);

      if (!session.isAuthenticated) {
        return isPublic ? null : '/sign-in';
      }
      if (isPublic) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (_, _) => const SignUpScreen()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),

      // Report detail (full-screen push from the tab).
      GoRoute(
        path: '/report/:id',
        builder: (_, state) => ReportDetailScreen(
          reportId: state.pathParameters['id']!,
        ),
      ),

      // Authenticated shell — 5 branches.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            TabShellScreen(navigationShell: navigationShell),
        branches: [
          // Home
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          // Log (opens the quick-log bottom sheet; landing is a hint)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/log',
                builder: (_, _) => const PlaceholderTab(
                  title: 'Log a symptom',
                  note: 'Tap the plus below to open the quick-log sheet from any tab. '
                      'You can also tap the CTA on the home dashboard.',
                ),
              ),
            ],
          ),
          // Report
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/report',
                builder: (_, _) => const RecentReportsScreen(),
              ),
            ],
          ),
          // Atlas
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/atlas',
                builder: (_, _) => const ChatScreen(),
              ),
            ],
          ),
          // Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(WidgetRef ref) {
    ref.listen(authControllerProvider, (prev, next) => notifyListeners());
  }
}