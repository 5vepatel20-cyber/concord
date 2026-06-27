import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/monitoring/posthog_init.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  @override
  void initState() {
    super.initState();
    capturePosthogEvent('landing_page_view');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.s5,
            Space.s6,
            Space.s5,
            Space.s6,
          ),
          children: [
            const SizedBox(height: Space.s5),
            Center(
              child: Icon(
                Icons.medical_services_outlined,
                size: 48,
                color: t.colorScheme.primary,
              ),
            ),
            const SizedBox(height: Space.s3),
            Text(
              'Concord',
              textAlign: TextAlign.center,
              style: t.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.s1),
            Text(
              'Understand your health records in plain language',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyLarge?.copyWith(color: Neutrals.slate),
            ),
            const SizedBox(height: Space.s6),
            Container(
              padding: const EdgeInsets.all(Space.s5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    t.colorScheme.primaryContainer,
                    t.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 32,
                    color: t.colorScheme.primary,
                  ),
                  const SizedBox(height: Space.s2),
                  Text(
                    'Decode My Doctor\'s Report',
                    style: t.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    'Paste or snap a photo of your medical document — '
                    'get a plain-language summary, flagged lab values, '
                    'medication list, and questions to ask your care team.',
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: Neutrals.slate,
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => context.push('/documents/decode'),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Decode a report — free'),
                      style: FilledButton.styleFrom(
                        textStyle: t.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.s5),
            _FeatureRow(
              icon: Icons.shield_outlined,
              title: 'Private & secure',
              subtitle: 'No account needed to decode. Your text is not stored.',
            ),
            const SizedBox(height: Space.s3),
            _FeatureRow(
              icon: Icons.trending_up_outlined,
              title: 'Track symptoms over time',
              subtitle:
                  'Sign up to log daily symptoms, spot worsening trends, and share reports with your care team.',
            ),
            const SizedBox(height: Space.s3),
            _FeatureRow(
              icon: Icons.auto_awesome_outlined,
              title: 'Ask Atlas',
              subtitle:
                  'Get AI-powered answers about your symptoms and treatment plan.',
            ),
            const SizedBox(height: Space.s6),
            Center(
              child: TextButton(
                onPressed: () => context.go('/sign-in'),
                child: const Text('Sign in to your account'),
              ),
            ),
            const SizedBox(height: Space.s1),
            Center(
              child: TextButton(
                onPressed: () => context.go('/sign-up'),
                child: const Text('Create an account'),
              ),
            ),
            const SizedBox(height: Space.s6),
            Center(
              child: Text(
                'Concord is not a medical device. Always follow your care team\'s guidance.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: t.colorScheme.primary),
        const SizedBox(width: Space.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: t.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
