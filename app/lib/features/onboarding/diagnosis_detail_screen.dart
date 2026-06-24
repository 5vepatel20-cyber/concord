import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens.dart';
import 'onboarding_controller.dart';

/// ONB-02: Diagnosis detail screen.
///
/// Branches UI by condition category:
///   - **Oncology**: diagnosis date, cancer stage (I–IV), treatment status,
///     regimen name (optional)
///   - **Other categories**: diagnosis date, treatment status
///
/// Can be used standalone (via router) or as part of the onboarding wizard.
class DiagnosisDetailScreen extends ConsumerStatefulWidget {
  const DiagnosisDetailScreen({super.key});

  @override
  ConsumerState<DiagnosisDetailScreen> createState() =>
      _DiagnosisDetailScreenState();
}

class _DiagnosisDetailScreenState extends ConsumerState<DiagnosisDetailScreen> {
  String? _selectedStage;
  late final TextEditingController _regimenCtrl;

  @override
  void initState() {
    super.initState();
    final state = ref.read(onboardingControllerProvider);
    _selectedStage = state.cancerStage.isNotEmpty ? state.cancerStage : null;
    _regimenCtrl = TextEditingController(text: state.regimenName);
  }

  @override
  void dispose() {
    _regimenCtrl.dispose();
    super.dispose();
  }

  bool get _isOncology => _category == 'oncology';
  String? get _category =>
      ref.watch(onboardingControllerProvider).conditionCategory;

  static const _stages = ['I', 'II', 'III', 'IV'];

  static const _stageLabels = {
    'I': 'Stage I',
    'II': 'Stage II',
    'III': 'Stage III',
    'IV': 'Stage IV',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = ref.watch(onboardingControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnosis details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.s5,
            Space.s3,
            Space.s5,
            Space.s6,
          ),
          children: [
            Text(
              'Tell us about your diagnosis',
              style: t.textTheme.headlineSmall,
            ),
            const SizedBox(height: Space.s2),
            Text(
              'Used to time-box symptom trends against your treatment plan.',
              style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
            ),
            const SizedBox(height: Space.s5),

            // ── Condition summary ──
            if (s.primaryConditionLabel.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(Space.s4),
                decoration: BoxDecoration(
                  color: BrandColors.concordBlueTint,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_hospital_outlined,
                      size: 20,
                      color: BrandColors.concordBlue,
                    ),
                    const SizedBox(width: Space.s2),
                    Expanded(
                      child: Text(
                        s.primaryConditionLabel,
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _category?.toUpperCase() ?? '',
                      style: t.textTheme.labelSmall?.copyWith(
                        color: BrandColors.concordBlue,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s5),
            ],

            // ── Diagnosis date ──
            Text('When were you diagnosed?', style: t.textTheme.titleSmall),
            const SizedBox(height: Space.s2),
            _DatePickerField(
              label: 'Diagnosis date',
              value: s.diagnosisDate,
              onChanged: (d) => ref
                  .read(onboardingControllerProvider.notifier)
                  .setDiagnosisDate(d),
            ),

            // ── Cancer stage (oncology only) ──
            if (_isOncology) ...[
              const SizedBox(height: Space.s5),
              Text('Cancer stage', style: t.textTheme.titleSmall),
              const SizedBox(height: Space.s2),
              Text(
                'Approximate stage at diagnosis — your care team can refine.',
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
              ),
              const SizedBox(height: Space.s2),
              SegmentedButton<String>(
                segments: _stages.map((stage) {
                  return ButtonSegment<String>(
                    value: stage,
                    label: Text(_stageLabels[stage]!),
                  );
                }).toList(),
                selected: _selectedStage == null ? {} : {_selectedStage!},
                onSelectionChanged: (sel) {
                  setState(() => _selectedStage = sel.first);
                  ref
                      .read(onboardingControllerProvider.notifier)
                      .setCancerStage(sel.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],

            // ── Regimen name (oncology only) ──
            if (_isOncology) ...[
              const SizedBox(height: Space.s5),
              TextField(
                controller: _regimenCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Treatment regimen (optional)',
                  hintText: 'e.g. AC-T, FOLFOX, Carboplatin + Paclitaxel',
                  helperText: 'Your chemo or drug combination name',
                ),
                onChanged: (v) => ref
                    .read(onboardingControllerProvider.notifier)
                    .setRegimenName(v),
              ),
            ],

            // ── Treatment status ──
            const SizedBox(height: Space.s5),
            Text('Where are you now?', style: t.textTheme.titleSmall),
            const SizedBox(height: Space.s2),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Neutrals.hairline),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Column(
                children: TreatmentStatus.values.map((ts) {
                  final selected = ts == s.treatmentStatus;
                  return RadioListTile<TreatmentStatus>(
                    title: Text(_treatmentStatusLabel(ts)),
                    subtitle: Text(
                      _treatmentStatusSubtitle(ts),
                      style: t.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? BrandColors.concordBlue
                            : Neutrals.slate,
                      ),
                    ),
                    value: ts,
                    // ignore: deprecated_member_use
                    groupValue: s.treatmentStatus,
                    // ignore: deprecated_member_use
                    onChanged: (v) => ref
                        .read(onboardingControllerProvider.notifier)
                        .setTreatmentStatus(v),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: Space.s6),

            // ── Save ──
            FilledButton(
              onPressed: _save,
              child: Text(_isOncology ? 'Save & continue' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final notifier = ref.read(onboardingControllerProvider.notifier);
    notifier.setRegimenName(_regimenCtrl.text.trim());
    notifier.next();
    context.pop();
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

String _treatmentStatusSubtitle(TreatmentStatus s) {
  switch (s) {
    case TreatmentStatus.activeTreatment:
      return 'Currently receiving chemo, radiation, immunotherapy, or targeted therapy';
    case TreatmentStatus.surveillance:
      return 'Finished a round of treatment, now monitoring with regular scans';
    case TreatmentStatus.remission:
      return 'No evidence of active disease';
    case TreatmentStatus.palliative:
      return 'Focusing on quality of life and symptom management';
  }
}

// ── Reusable date picker field ──

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
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
