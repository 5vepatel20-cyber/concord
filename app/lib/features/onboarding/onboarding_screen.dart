// Onboarding wizard — 6 linear steps. No skip button per spec (clinical app
// must complete onboarding before exposing patient features).
//
// Step layout:
//   0 ONB-01 — full name
//   1 ONB-01 — condition selection (coded)
//   2 ONB-02 — diagnosis details (date, stage, treatment_status)
//   3 ONB-03 — date of birth + sex_at_birth
//   4 ONB-07 — HealthKit / Health Connect permission priming
//   5 ONB-06 — consent + "not a medical device" disclaimer (versioned)

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/health/health_repository.dart';
import '../../data/models/condition.dart';
import '../../data/repositories/vocab_repository.dart';
import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../profile/settings_storage.dart';
import 'onboarding_controller.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Setup · step ${state.step + 1} of ${OnboardingState.totalSteps}',
        ),
        leading: state.step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    ref.read(onboardingControllerProvider.notifier).back(),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.s5),
          child: switch (state.step) {
            0 => const _StepName(),
            1 => const _StepCondition(),
            2 => const _StepDiagnosis(),
            3 => const _StepDemographics(),
            4 => const _StepHealthPriming(),
            5 => const _StepConsent(),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

// ── Step 0: name ──────────────────────────────────────────────────────────────

class _StepName extends ConsumerStatefulWidget {
  const _StepName();
  @override
  ConsumerState<_StepName> createState() => _StepNameState();
}

class _StepNameState extends ConsumerState<_StepName> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: ref.read(onboardingControllerProvider).fullName,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What\'s your name?', style: t.textTheme.headlineSmall),
        const SizedBox(height: Space.s2),
        Text(
          'We use this in your reports and to greet you.',
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s5),
        TextField(
          controller: _ctrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
          onChanged: (v) =>
              ref.read(onboardingControllerProvider.notifier).setName(v),
        ),
        const Spacer(),
        FilledButton(
          onPressed: state.isStep0Valid
              ? () => ref.read(onboardingControllerProvider.notifier).next()
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

// ── Step 1: condition selection ──────────────────────────────────────────────

class _StepCondition extends ConsumerStatefulWidget {
  const _StepCondition();
  @override
  ConsumerState<_StepCondition> createState() => _StepConditionState();
}

class _StepConditionState extends ConsumerState<_StepCondition> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _categoryLabels = {
    'oncology': 'Cancer types',
    'cardiometabolic': 'Cardiovascular & metabolic',
    'autoimmune': 'Autoimmune',
    'respiratory': 'Respiratory',
    'mental_health': 'Mental health',
    'other': 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    final vocabAsync = ref.watch(vocabSnapshotProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What condition are you being treated for?',
          style: t.textTheme.headlineSmall,
        ),
        const SizedBox(height: Space.s2),
        Text(
          'Pick the closest match. Your care team can refine this later.',
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s4),
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Search conditions…',
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        const SizedBox(height: Space.s3),
        Expanded(
          child: vocabAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Couldn\'t load conditions: $e')),
            data: (snapshot) {
              final filtered = _query.isEmpty
                  ? snapshot
                  : snapshot.where((c) {
                      final name = c.condition.displayName.toLowerCase();
                      final code = c.condition.icd10Code?.toLowerCase() ?? '';
                      return name.contains(_query) || code.contains(_query);
                    }).toList();

              // Group by category, preserving original order.
              final grouped = <String, List<ConditionWithTerms>>{};
              for (final c in filtered) {
                grouped.putIfAbsent(c.condition.category, () => []);
                grouped[c.condition.category]!.add(c);
              }

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No conditions loaded.'
                        : 'No conditions match "$_query".',
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: Neutrals.hint,
                    ),
                  ),
                );
              }

              return ListView(
                children: [
                  for (final entry in grouped.entries) ...[
                    if (entry.value.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.only(
                          top: entry.key == grouped.keys.first ? 0 : Space.s3,
                          bottom: Space.s1,
                        ),
                        child: Text(
                          _categoryLabels[entry.key] ?? entry.key,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: Neutrals.hint,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      for (final c in entry.value)
                        RadioListTile<String>(
                          dense: true,
                          title: Text(c.condition.displayName),
                          subtitle: c.condition.icd10Code == null
                              ? null
                              : Text('ICD-10: ${c.condition.icd10Code}'),
                          value: c.condition.id,
                          // ignore: deprecated_member_use
                          groupValue: state.primaryConditionId,
                          // ignore: deprecated_member_use
                          onChanged: (v) {
                            if (v == null) return;
                            ref
                                .read(onboardingControllerProvider.notifier)
                                .setCondition(
                                  id: v,
                                  label: c.condition.displayName,
                                );
                          },
                        ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
        FilledButton(
          onPressed: state.isStep1Valid
              ? () => ref.read(onboardingControllerProvider.notifier).next()
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

// ── Step 2: diagnosis details ────────────────────────────────────────────────

class _StepDiagnosis extends ConsumerWidget {
  const _StepDiagnosis();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    return ListView(
      children: [
        Text('Tell us about your diagnosis', style: t.textTheme.headlineSmall),
        const SizedBox(height: Space.s2),
        Text(
          'Used to time-box symptom trends against your treatment plan.',
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s5),
        _DatePickerField(
          label: 'Approximate diagnosis date',
          value: state.diagnosisDate,
          onChanged: (d) => ref
              .read(onboardingControllerProvider.notifier)
              .setDiagnosisDate(d),
        ),
        const SizedBox(height: Space.s4),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Stage (e.g. IIA, IV)',
            hintText: 'I, II, III, IV — your care team can clarify',
          ),
          textCapitalization: TextCapitalization.characters,
          onChanged: (v) =>
              ref.read(onboardingControllerProvider.notifier).setCancerStage(v),
        ),
        const SizedBox(height: Space.s5),
        Text('Where are you now?', style: t.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        ...TreatmentStatus.values.map(
          (s) => RadioListTile<TreatmentStatus>(
            title: Text(_treatmentStatusLabel(s)),
            value: s,
            // ignore: deprecated_member_use
            groupValue: state.treatmentStatus,
            // ignore: deprecated_member_use
            onChanged: (v) => ref
                .read(onboardingControllerProvider.notifier)
                .setTreatmentStatus(v),
          ),
        ),
        const SizedBox(height: Space.s5),
        FilledButton(
          onPressed: state.isStep2Valid
              ? () => ref.read(onboardingControllerProvider.notifier).next()
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

String _treatmentStatusLabel(TreatmentStatus s) {
  switch (s) {
    case TreatmentStatus.activeTreatment:
      return 'On active treatment';
    case TreatmentStatus.surveillance:
      return 'Surveillance / between treatments';
    case TreatmentStatus.remission:
      return 'In remission';
    case TreatmentStatus.palliative:
      return 'Palliative care';
  }
}

// ── Step 3: demographics ─────────────────────────────────────────────────────

class _StepDemographics extends ConsumerWidget {
  const _StepDemographics();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    return ListView(
      children: [
        Text('A bit more about you', style: t.textTheme.headlineSmall),
        const SizedBox(height: Space.s2),
        Text(
          'We use age and sex-at-birth only to interpret your symptoms — they never leave your account.',
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s5),
        _DatePickerField(
          label: 'Date of birth',
          value: state.dateOfBirth,
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
          onChanged: (d) =>
              ref.read(onboardingControllerProvider.notifier).setDateOfBirth(d),
        ),
        const SizedBox(height: Space.s4),
        Text('Sex at birth', style: t.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          children: [
            for (final s in const [
              'female',
              'male',
              'intersex',
              'prefer_not_to_say',
            ])
              ChoiceChip(
                label: Text(_sexLabel(s)),
                selected: state.sexAtBirth == s,
                onSelected: (_) => ref
                    .read(onboardingControllerProvider.notifier)
                    .setSexAtBirth(s),
              ),
          ],
        ),
        const SizedBox(height: Space.s6),
        FilledButton(
          onPressed: state.isStep3Valid
              ? () => ref.read(onboardingControllerProvider.notifier).next()
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

String _sexLabel(String s) {
  switch (s) {
    case 'female':
      return 'Female';
    case 'male':
      return 'Male';
    case 'intersex':
      return 'Intersex';
    case 'prefer_not_to_say':
      return 'Prefer not to say';
  }
  return s;
}

// ── Step 4: HealthKit / Health Connect permission priming (ONB-07) ──────────

class _StepHealthPriming extends ConsumerWidget {
  const _StepHealthPriming();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    return ListView(
      children: [
        Text('Connect your health data', style: t.textTheme.headlineSmall),
        const SizedBox(height: Space.s2),
        Text(
          'Concord can read your Apple Health or Google Fit data to give you a fuller picture alongside your symptoms.',
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s5),
        _HealthMetricTile(
          icon: Icons.directions_walk,
          title: 'Steps',
          subtitle: 'See how your activity level changes with treatment.',
        ),
        const SizedBox(height: Space.s2),
        _HealthMetricTile(
          icon: Icons.favorite_outline,
          title: 'Heart rate',
          subtitle: 'Resting and average heart rate trends over time.',
        ),
        const SizedBox(height: Space.s2),
        _HealthMetricTile(
          icon: Icons.bedtime_outlined,
          title: 'Sleep',
          subtitle: 'Duration and quality — chemo often disrupts sleep.',
        ),
        const SizedBox(height: Space.s2),
        _HealthMetricTile(
          icon: Icons.monitor_weight_outlined,
          title: 'Weight',
          subtitle:
              'Track weight changes that may signal fluid shifts or nutrition needs.',
        ),
        const SizedBox(height: Space.s5),
        Text(
          'You can always connect or disconnect health data later in Settings.',
          style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s3),
        SwitchListTile(
          value: state.connectHealthEnabled,
          onChanged: (v) => ref
              .read(onboardingControllerProvider.notifier)
              .setConnectHealthEnabled(v),
          title: const Text('Connect health data now'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: Space.s5),
        FilledButton(
          onPressed: () =>
              ref.read(onboardingControllerProvider.notifier).next(),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _HealthMetricTile extends StatelessWidget {
  const _HealthMetricTile({
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
      children: [
        Icon(icon, color: t.colorScheme.primary, size: 24),
        const SizedBox(width: Space.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.textTheme.titleSmall),
              const SizedBox(height: Space.s1),
              Text(
                subtitle,
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 5: consent + submit ─────────────────────────────────────────────────

class _StepConsent extends ConsumerStatefulWidget {
  const _StepConsent();
  @override
  ConsumerState<_StepConsent> createState() => _StepConsentState();
}

class _StepConsentState extends ConsumerState<_StepConsent> {
  bool _busy = false;
  String? _error;

  static const _disclaimerVersion = '2026-06-22';

  Future<void> _submit() async {
    final s = ref.read(onboardingControllerProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) throw StateError('Not signed in');

      final dobStr = s.dateOfBirth?.toIso8601String().split('T').first;
      final dxStr = s.diagnosisDate?.toIso8601String().split('T').first;
      if (dobStr == null) throw StateError('Date of birth required');

      final body = jsonEncode({
        'full_name': s.fullName,
        'date_of_birth': dobStr,
        'sex_at_birth': s.sexAtBirth,
        'primary_diagnosis_id': s.primaryConditionId,
        'diagnosis_date': dxStr,
        'cancer_stage': s.cancerStage.isEmpty ? null : s.cancerStage,
        'treatment_status': treatmentStatusToString(s.treatmentStatus),
        'consent_version': _disclaimerVersion,
      });

      final res = await http.post(
        Uri.parse('$apiBase/api/onboarding/submit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: body,
      );

      if (res.statusCode != 200) {
        throw StateError('Onboarding failed: ${res.statusCode} ${res.body}');
      }

      if (!mounted) return;
      await ref
          .read(settingsControllerProvider.notifier)
          .setConsentVersion(_disclaimerVersion);

      if (s.connectHealthEnabled) {
        try {
          final health = ref.read(healthRepositoryProvider);
          await health.requestPermission();
        } catch (_) {}
      }

      if (!mounted) return;
      ref.read(onboardingControllerProvider.notifier).setStep(0);
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    return ListView(
      children: [
        Text('Before you start', style: t.textTheme.headlineSmall),
        const SizedBox(height: Space.s2),
        Text(
          'Concord helps you track symptoms between visits. It is not a medical device and does not replace your care team.',
          style: t.textTheme.bodyMedium,
        ),
        const SizedBox(height: Space.s5),
        Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: SeverityColors.moderate.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: SeverityColors.moderate, width: 1),
          ),
          child: Text(
            'If you are experiencing a medical emergency, call your local emergency number or go to the nearest emergency department.',
            style: t.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: Space.s5),
        CheckboxListTile(
          value: state.consentAccepted,
          onChanged: (v) => ref
              .read(onboardingControllerProvider.notifier)
              .setConsentAccepted(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'I agree to the disclaimer (v$_disclaimerVersion) and consent to storing my symptom data in Concord.',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.s3),
          Text(
            _error!,
            style: t.textTheme.bodySmall?.copyWith(
              color: SeverityColors.severe,
            ),
          ),
        ],
        const SizedBox(height: Space.s5),
        FilledButton(
          onPressed: !state.isStep5Valid || _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Finish setup'),
        ),
      ],
    );
  }
}

// ── Reusable date picker field ───────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: firstDate ?? DateTime(2000),
          lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
        );
        onChanged(picked);
      },
      borderRadius: BorderRadius.circular(Radii.md),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(
          value == null
              ? 'Tap to choose'
              : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}
