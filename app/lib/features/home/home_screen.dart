// Home dashboard — the patient's daily landing surface.
//
// Shows:
//   - Today's date + a "Good morning" greeting (uses the user's first name)
//   - "Log a symptom" CTA that opens the quick-log bottom sheet
//   - Recent reports count (placeholder for Step 8)
//   - Latest Atlas nudge (placeholder for Step 9)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../symptoms/quick_log_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _firstNameFromEmail(String? email) {
    if (email == null || email.isEmpty) return 'there';
    final local = email.split('@').first;
    // strip digits and dot-separators, then take the first chunk
    final first = local.split(RegExp(r'[._\d]')).firstWhere(
          (s) => s.isNotEmpty,
          orElse: () => local,
        );
    return first[0].toUpperCase() + first.substring(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE, MMM d').format(now);
    final greeting = _greetingFor(now);
    final firstName = _firstNameFromEmail(user?.email);

    return Scaffold(
      appBar: AppBar(
        title: Text(dateLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign out',
            onPressed: () {
              // signOut() is wired in auth_controller; for Step 6 we leave the
              // icon visible but the action is owned by Profile/Settings.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Use Profile → Sign out to leave.')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.s5, Space.s2, Space.s5, Space.s6,
          ),
          children: [
            Text(
              '$greeting, $firstName',
              style: t.textTheme.headlineMedium,
            ),
            const SizedBox(height: Space.s2),
            Text(
              'How are you feeling today?',
              style: t.textTheme.bodyLarge?.copyWith(color: Neutrals.slate),
            ),
            const SizedBox(height: Space.s5),
            _LogSymptomCta(
              onTap: () => QuickLogScreen.show(context),
            ),
            const SizedBox(height: Space.s6),
            _Section(
              title: 'Recent reports',
              child: _RecentReportsCard(),
            ),
            const SizedBox(height: Space.s5),
            _Section(
              title: 'Atlas says',
              child: _AtlasNudgeCard(),
            ),
          ],
        ),
      ),
    );
  }

  String _greetingFor(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _LogSymptomCta extends StatelessWidget {
  const _LogSymptomCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        padding: const EdgeInsets.all(Space.s5),
        decoration: BoxDecoration(
          color: t.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline,
                size: 32, color: t.colorScheme.onPrimaryContainer),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Log a symptom',
                    style: t.textTheme.titleMedium
                        ?.copyWith(color: t.colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    'Takes about 30 seconds',
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: t.colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: t.colorScheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.textTheme.titleMedium),
        const SizedBox(height: Space.s2),
        child,
      ],
    );
  }
}

class _RecentReportsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Row(
          children: [
            Icon(Icons.assignment_outlined, color: t.colorScheme.primary),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                'No reports yet — your first symptom log will create one.',
                style: t.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AtlasNudgeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Row(
          children: [
            const Text('✨', style: TextStyle(fontSize: 24)),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                'Ask Atlas to summarize how you\'ve been doing this week.',
                style: t.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}