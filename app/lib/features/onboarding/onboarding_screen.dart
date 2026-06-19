// Onboarding wizard — 6 linear steps. No skip button per spec (clinical app
// must complete onboarding before exposing patient features).
//
// Step layout:
//   0 ONB-01 — full name
//   1 ONB-02 — condition selection (coded)
//   2 ONB-03 — diagnosis details (date, stage, treatment_status)
//   3 ONB-04 — date of birth + sex_at_birth
//   4 placeholder (caregiver invite — deferred to 1.1)
//   5 ONB-06 — consent + "not a medical device" disclaimer (versioned)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        title: Text('Setup · step ${state.step + 1} of ${OnboardingState.totalSteps}'),
        leading: state.step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => ref
                    .read(onboardingControllerProvider.notifier)
                    .back(),
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
            4 => const _StepCaregiverPlaceholder(),
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
    _ctrl = TextEditingController(text: ref.read(onboardingControllerProvider).fullName);
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

class _StepCondition extends ConsumerWidget {
  const _StepCondition();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    final vocabAsync = ref.watch(vocabSnapshotProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What condition are you being treated for?',
            style: t.textTheme.headlineSmall),
        const SizedBox(height: Space.s2),
        Text(
          'Pick the closest match. Your care team can refine this later.',
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s5),
        Expanded(
          child: vocabAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Couldn\'t load conditions: $e'),
            ),
            data: (snapshot) => ListView(
              children: [
                for (final c in snapshot)
                  RadioListTile<String>(
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
                          .setCondition(id: v, label: c.condition.displayName);
                    },
                  ),
              ],
            ),
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
          onChanged: (v) => ref
              .read(onboardingControllerProvider.notifier)
              .setCancerStage(v),
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
          onChanged: (d) => ref
              .read(onboardingControllerProvider.notifier)
              .setDateOfBirth(d),
        ),
        const SizedBox(height: Space.s4),
        Text('Sex at birth', style: t.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          children: [
            for (final s in const ['female', 'male', 'intersex', 'prefer_not_to_say'])
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
    case 'female': return 'Female';
    case 'male': return 'Male';
    case 'intersex': return 'Intersex';
    case 'prefer_not_to_say': return 'Prefer not to say';
  }
  return s;
}

// ── Step 4: caregiver placeholder ────────────────────────────────────────────

class _StepCaregiverPlaceholder extends ConsumerWidget {
  const _StepCaregiverPlaceholder();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Caregivers', style: t.textTheme.headlineSmall),
        const SizedBox(height: Space.s2),
        Text(
          'Soon you\'ll be able to invite a family member or care navigator to view your reports with you. For now, that\'s all set up by your care team.',
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const Spacer(),
        FilledButton(
          onPressed: () => ref.read(onboardingControllerProvider.notifier).next(),
          child: const Text('Continue'),
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

  static const _disclaimerVersion = '2026-06-19';

  Future<void> _submit() async {
    final state = ref.read(onboardingControllerProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = supabase.auth.currentUser;
      if (user == null) throw StateError('Not signed in');

      // 1. user row (full_name, dob, sex_at_birth, locale).
      await supabase.from('user').upsert({
        'id': user.id,
        'email': user.email,
        'full_name': state.fullName,
        'date_of_birth': state.dateOfBirth?.toIso8601String().split('T').first,
        'sex_at_birth': state.sexAtBirth,
        'locale': 'en',
      });

      // 2. patient_profile row (primary_diagnosis_id, diagnosis_date, stage, status).
      final dob = state.diagnosisDate;
      await supabase.from('patient_profile').upsert({
        'user_id': user.id,
        'primary_diagnosis_id': state.primaryConditionId,
        'diagnosis_date': dob?.toIso8601String().split('T').first,
        'cancer_stage': state.cancerStage,
        'treatment_status': treatmentStatusToString(state.treatmentStatus),
      });

      if (!mounted) return;
      // Persist the consent version the user just accepted.
      await ref
          .read(settingsControllerProvider.notifier)
          .setConsentVersion(_disclaimerVersion);
      if (!mounted) return;
      // Reset controller for a clean re-entry, then go home.
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
            style: t.textTheme.bodySmall?.copyWith(color: SeverityColors.severe),
          ),
        ],
        const SizedBox(height: Space.s5),
        FilledButton(
          onPressed: !state.isStep5Valid || _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18, width: 18,
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