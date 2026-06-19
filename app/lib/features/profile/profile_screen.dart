// Profile + settings screen.
//
// Sections: Account, Privacy, Data, About.
// - Account: email, sign out (wipes keychain).
// - Privacy: PostHog opt-in toggle (default off, persisted locally).
// - Data: consent version (read-only — captured at onboarding).
// - About: app version + privacy policy link stub.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import 'settings_storage.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final settingsAsync = ref.watch(settingsControllerProvider);
    final supabase = ref.watch(supabaseClientProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.s5, Space.s3, Space.s5, Space.s6,
          ),
          children: [
            // Account
            _SectionHeader('Account'),
            _SettingsCard(children: [
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email'),
                subtitle: Text(user?.email ?? '(not signed in)'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: SeverityColors.severe),
                title: const Text('Sign out'),
                textColor: SeverityColors.severe,
                onTap: () async {
                  await supabase.auth.signOut();
                  if (context.mounted) context.go('/sign-in');
                },
              ),
            ]),

            // Privacy
            const SizedBox(height: Space.s5),
            _SectionHeader('Privacy'),
            _SettingsCard(children: [
              settingsAsync.when(
                loading: () => const ListTile(
                  leading: Icon(Icons.analytics_outlined),
                  title: Text('Product analytics'),
                  subtitle: Text('Loading…'),
                ),
                error: (e, _) => ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Product analytics'),
                  subtitle: Text('Error: $e'),
                ),
                data: (s) => SwitchListTile(
                  secondary: const Icon(Icons.analytics_outlined),
                  title: const Text('Product analytics'),
                  subtitle: const Text(
                    'Share anonymous usage to help us improve. Off by default.',
                  ),
                  value: s.posthogOptIn,
                  onChanged: (v) => ref
                      .read(settingsControllerProvider.notifier)
                      .setPosthogOptIn(v),
                ),
              ),
            ]),

            // Data
            const SizedBox(height: Space.s5),
            _SectionHeader('Data'),
            _SettingsCard(children: [
              settingsAsync.when(
                loading: () => const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('Consent'),
                  subtitle: Text('Loading…'),
                ),
                error: (e, _) => ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Consent'),
                  subtitle: Text('Error: $e'),
                ),
                data: (s) => ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Disclaimer & consent'),
                  subtitle: Text(
                    s.consentVersion == null
                        ? 'Not yet accepted'
                        : 'Version ${s.consentVersion}',
                  ),
                ),
              ),
            ]),

            // About
            const SizedBox(height: Space.s5),
            _SectionHeader('About'),
            _SettingsCard(children: [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Version'),
                subtitle: Text('1.0.0 (build 1)'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy policy'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Privacy policy link coming soon.')),
                  );
                },
              ),
            ]),
            const SizedBox(height: Space.s4),
            Text(
              'Concord is not a medical device. It helps you track symptoms '
              'between visits. Always follow your care team\'s guidance.',
              style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s1, 0, 0, Space.s2,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Neutrals.slate,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}