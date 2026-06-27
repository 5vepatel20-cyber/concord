import 'package:concord/features/landing/landing_screen.dart';
import 'package:concord/theme/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const LandingScreen()),
        GoRoute(
          path: '/sign-in',
          builder: (_, __) => const Scaffold(body: Text('Sign In')),
        ),
        GoRoute(
          path: '/sign-up',
          builder: (_, __) => const Scaffold(body: Text('Sign Up')),
        ),
        GoRoute(
          path: '/documents/decode',
          builder: (_, __) => const Scaffold(body: Text('Decode')),
        ),
      ],
    );
    return MaterialApp.router(theme: buildConcordTheme(), routerConfig: router);
  }

  testWidgets('renders Concord branding and tagline', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Concord'), findsOneWidget);
    expect(
      find.text('Understand your health records in plain language'),
      findsOneWidget,
    );
  });

  testWidgets('renders Decode My Doctor\'s Report section with CTA button', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text("Decode My Doctor's Report"), findsOneWidget);
    expect(find.text('Decode a report — free'), findsOneWidget);
  });

  testWidgets('renders feature rows', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Private & secure'), findsOneWidget);
    expect(find.text('Track symptoms over time'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ask Atlas'), 100);
    expect(find.text('Ask Atlas'), findsOneWidget);
  });

  testWidgets('renders sign in and create account buttons', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Sign in to your account'), 100);
    await tester.scrollUntilVisible(find.text('Create an account'), 100);
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });

  testWidgets('renders medical disclaimer', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining("Concord is not a medical device"),
      100,
    );
    expect(
      find.textContaining("Concord is not a medical device"),
      findsOneWidget,
    );
  });

  testWidgets('tapping Decode a report navigates to /documents/decode', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Decode a report — free'));
    await tester.pumpAndSettle();

    expect(find.text('Decode'), findsOneWidget);
  });

  testWidgets('tapping Sign in navigates to /sign-in', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Sign in to your account'), 100);
    await tester.ensureVisible(find.text('Sign in to your account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in to your account'));
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('tapping Create an account navigates to /sign-up', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Create an account'), 100);
    await tester.ensureVisible(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Sign Up'), findsOneWidget);
  });
}
