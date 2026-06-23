// Profile + settings screen.
//
// Sections: Account, Reminders, Privacy, Data, About.
// - Account: email, sign out (wipes keychain).
// - Reminders: daily check-in toggle + time picker (SYM-03).
// - Privacy: PostHog opt-in toggle (default off, persisted locally).
// - Data: consent version (read-only — captured at onboarding).
// - About: app version + privacy policy link stub.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_service.dart';
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
            Space.s5,
            Space.s3,
            Space.s5,
            Space.s6,
          ),
          children: [
            // Account
            _SectionHeader('Account'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Email'),
                  subtitle: Text(user?.email ?? '(not signed in)'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.logout,
                    color: SeverityColors.severe,
                  ),
                  title: const Text('Sign out'),
                  textColor: SeverityColors.severe,
                  onTap: () async {
                    await supabase.auth.signOut();
                    if (context.mounted) context.go('/sign-in');
                  },
                ),
              ],
            ),

            // Medications (MED-01..06).
            const SizedBox(height: Space.s5),
            _SectionHeader('Medications'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.medication_outlined),
                  title: const Text('Manage medications'),
                  subtitle: const Text(
                    'Track what you take, when, and whether doses were taken or missed.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/medications'),
                ),
              ],
            ),

            // Manual vitals entry (HK-03) + health metrics history (HK-04).
            const SizedBox(height: Space.s5),
            _SectionHeader('Vitals'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('Log vitals'),
                  subtitle: const Text(
                    'Enter weight, blood pressure, heart rate, or blood glucose manually.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/vitals/manual'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.trending_up_outlined),
                  title: const Text('Health trends'),
                  subtitle: const Text(
                    'View charts and history for your tracked health metrics.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/health/metrics'),
                ),
              ],
            ),

            // Clinical trials search (TRIAL-01).
            const SizedBox(height: Space.s5),
            _SectionHeader('Research'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.biotech_outlined),
                  title: const Text('Clinical trials'),
                  subtitle: const Text(
                    'Search ClinicalTrials.gov for studies relevant to your condition.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/trials/search'),
                ),
              ],
            ),

            // Treatment calendar (ONB-05).
            const SizedBox(height: Space.s5),
            _SectionHeader('Treatment'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Treatment calendar'),
                  subtitle: const Text(
                    'Track infusion, appointment, lab, and scan dates.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/treatment/calendar'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.iv_bag),
                  title: const Text('Chemo regimens'),
                  subtitle: const Text(
                    'Create cyclical chemo schedule templates.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/treatment/regimens'),
                ),
              ],
            ),

            // Care team management (CARE-01) + caregiver dashboard (SYM-08).
            const SizedBox(height: Space.s5),
            _SectionHeader('Care team'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.favorite_outline),
                  title: const Text('Manage care team'),
                  subtitle: const Text(
                    'Invite caregivers to view your data and receive alerts.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/caregiver/manage'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text('Caregiver dashboard'),
                  subtitle: const Text(
                    'Log symptoms for someone you care for.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/caregiver/dashboard'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: const Text('Escalation policies'),
                  subtitle: const Text(
                    'Route alerts by severity, time, and role.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/alerts/policies'),
                ),
              ],
            ),
            const SizedBox(height: Space.s5),
            _SectionHeader('Messages'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('Inbox'),
                  subtitle: const Text(
                    'Secure messages with your care team.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/messages'),
                ),
              ],
            ),
              ],
            ),

            // Document decode (DOC-01..05).
            const SizedBox(height: Space.s5),
            _SectionHeader('Documents'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Decode a document'),
                  subtitle: const Text(
                    'Upload or paste medical documents for AI-powered plain-language summary and lab flagging.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/documents/decode'),
                ),
              ],
            ),

            // Reminders (SYM-03).
            const SizedBox(height: Space.s5),
            _SectionHeader('Reminders'),
            _SettingsCard(
              children: [
                settingsAsync.when(
                  loading: () => const ListTile(
                    leading: Icon(Icons.notifications_active_outlined),
                    title: Text('Daily check-in'),
                    subtitle: Text('Loading…'),
                  ),
                  error: (e, _) => ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Daily check-in'),
                    subtitle: Text('Error: $e'),
                  ),
                  data: (s) => Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: const Text('Daily check-in'),
                        subtitle: const Text(
                          'A gentle daily reminder to log how you are feeling.',
                        ),
                        value: s.dailyCheckInEnabled,
                        onChanged: (v) => ref
                            .read(settingsControllerProvider.notifier)
                            .setDailyCheckInEnabled(v),
                      ),
                      if (s.dailyCheckInEnabled) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.schedule_outlined),
                          title: const Text('Time'),
                          subtitle: Text(s.dailyCheckInTime.toString()),
                          trailing: TextButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: s.dailyCheckInTime.hour,
                                  minute: s.dailyCheckInTime.minute,
                                ),
                              );
                              if (picked != null) {
                                await ref
                                    .read(settingsControllerProvider.notifier)
                                    .setDailyCheckInTime(
                                      TimeOfDayHHMM(picked.hour, picked.minute),
                                    );
                              }
                            },
                            child: const Text('Change'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Privacy
            const SizedBox(height: Space.s5),
            _SectionHeader('Privacy'),
            _SettingsCard(
              children: [
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
              ],
            ),

            // Data
            const SizedBox(height: Space.s5),
            _SectionHeader('Data'),
            _SettingsCard(
              children: [
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
              ],
            ),

            // About
            const SizedBox(height: Space.s5),
            _SectionHeader('About'),
            _SettingsCard(
              children: [
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
                      const SnackBar(
                        content: Text('Privacy policy link coming soon.'),
                      ),
                    );
                  },
                ),
              ],
            ),
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
      padding: const EdgeInsets.fromLTRB(Space.s1, 0, 0, Space.s2),
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
