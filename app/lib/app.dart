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
//
// Deep links:
//   - concord://log → /log (from notification taps / future share sheets)
//   - concord://report/<id> → /report/:id
//   - concord://atlas → /atlas

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/notifications/notification_service.dart';
import 'features/atlas/chat_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/sign_up_screen.dart';
import 'features/documents/document_decode_screen.dart';
import 'features/home/home_screen.dart';
import 'features/log/log_landing_screen.dart';
import 'features/medications/medications_screen.dart';
import 'features/medications/add_medication_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/settings_storage.dart';
import 'features/report/recent_reports_screen.dart';
import 'features/report/report_detail_screen.dart';
import 'features/symptoms/symptom_history_screen.dart';
import 'features/tab_shell.dart';
import 'theme/theme_data.dart';

class ConcordApp extends ConsumerStatefulWidget {
  const ConcordApp({super.key});

  @override
  ConsumerState<ConcordApp> createState() => _ConcordAppState();
}

class _ConcordAppState extends ConsumerState<ConcordApp> {
  late final GoRouter _router;
  StreamSubscription<String>? _tapSub;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(ref);

    final notif = ref.read(notificationServiceProvider);

    // Cold-start deep link: if the app was launched from a notification
    // tap, NotificationService recorded the payload before runApp.
    // Schedule a post-frame jump so the router is ready.
    final cold = notif.initialPayload;
    if (cold != null && cold.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _router.go(cold);
      });
    }

    // Warm-start deep link: subscribe to taps that fire while the app
    // is already running. Each event is a notification payload (a
    // route path like '/log' or '/medications'). The router handles
    // auth redirects so a tap before sign-in lands on /sign-in.
    _tapSub = notif.tapStream.listen(_routeFor);
  }

  void _routeFor(String payload) {
    if (!mounted) return;
    _router.go(payload);
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    super.dispose();
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

      // Onboarding guard: redirect to /onboarding until consent is stored.
      if (loc != '/onboarding') {
        final settings = ref.read(settingsControllerProvider);
        if (settings is AsyncData && settings.value?.consentVersion == null) {
          return '/onboarding';
        }
      }

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

      // Medications (MED-01..06). Full-screen push from Profile.
      GoRoute(
        path: '/medications',
        builder: (_, _) => const MedicationsScreen(),
      ),
      GoRoute(
        path: '/medications/add',
        builder: (_, _) => const AddMedicationScreen(),
      ),

      // Symptom history (SYM-07). Full-screen push from Home.
      GoRoute(
        path: '/symptom-history',
        builder: (_, _) => const SymptomHistoryScreen(),
      ),

      // Documents (DOC-01..05). Full-screen push from Profile.
      GoRoute(
        path: '/documents/decode',
        builder: (_, _) => const DocumentDecodeScreen(),
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
          // Log (opens the quick-log bottom sheet on mount, then
          // routes to /home so the sheet is layered over the home tab)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/log',
                builder: (_, _) => const LogLandingScreen(),
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