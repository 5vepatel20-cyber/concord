// Symptom quick-log screen — bottom sheet that lets a patient log a structured
// symptom report in under 30 seconds. Backed by VocabRepository for the panel
// of conditions+terms and SymptomRepository for offline-first submission.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../core/voice/speech_service.dart';
import '../../data/models/condition.dart';
import '../../data/repositories/symptom_repository.dart';
import '../../data/repositories/vocab_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/severity_chip.dart';

/// Bottom sheet. Always wraps content in the bottom sheet; close button is the
/// native drag handle + scrim tap.
class QuickLogScreen extends ConsumerWidget {
  const QuickLogScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const QuickLogScreen(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vocabAsync = ref.watch(vocabSnapshotProvider);
    return _SheetScaffold(
      child: vocabAsync.when(
        loading: () => const _CenteredLoading(),
        error: (e, _) => _ErrorState(message: 'Couldn\'t load symptoms: $e'),
        data: (snapshot) => _QuickLogForm(snapshot: snapshot),
      ),
    );
  }
}

// ── Sheet chrome ──────────────────────────────────────────────────────────────

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: Space.s2),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Neutrals.mist,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: Space.s3),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _CenteredLoading extends StatelessWidget {
  const _CenteredLoading();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.s5),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

// ── Form ─────────────────────────────────────────────────────────────────────

class _QuickLogForm extends ConsumerStatefulWidget {
  const _QuickLogForm({required this.snapshot});
  final List<ConditionWithTerms> snapshot;

  @override
  ConsumerState<_QuickLogForm> createState() => _QuickLogFormState();
}

class _QuickLogFormState extends ConsumerState<_QuickLogForm> {
  String? _selectedConditionId;
  final Map<String, int> _responses = {}; // symptom_term_id -> grade
  final _notes = TextEditingController();
  String _source = 'self';
  RecallWindow _recall = RecallWindow.now;
  bool _busy = false;
  String? _error;
  String? _emergencyGuidance;

  // ── SYM-05 voice input state ──
  bool _speechReady = false;     // init() returned true (plugin available)
  bool _isListening = false;     // actively listening right now
  bool _hadFinalBefore = false;  // last utterance for this mic session ended in a final
  int _lastPartialLength = 0;    // char count of the partial currently appended to notes
  StreamSubscription<SpeechEvent>? _speechSub;

  List<VocabSymptomTerm> get _termsForCondition {
    final id = _selectedConditionId;
    if (id == null) return const [];
    for (final c in widget.snapshot) {
      if (c.condition.id == id) return c.terms;
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final service = ref.read(speechServiceProvider);
    final ok = await service.init();
    if (!mounted) return;
    setState(() => _speechReady = ok);
    if (ok) {
      _speechSub = service.events.listen(_onSpeechEvent);
    }
  }

  void _onSpeechEvent(SpeechEvent event) {
    if (!mounted) return;
    switch (event) {
      case SpeechPartial(:final text):
        setState(() {
          _notes.text = appendTranscript(
            _notes.text,
            text,
            isFinal: false,
            hadFinalBefore: _hadFinalBefore,
            prevPartialLength: _lastPartialLength,
          );
          _lastPartialLength = text.trimLeft().length;
          // Keep cursor at the end so the user sees the live partial.
          _notes.selection = TextSelection.collapsed(
            offset: _notes.text.length,
          );
        });
      case SpeechFinal(:final text):
        setState(() {
          _notes.text = appendTranscript(
            _notes.text,
            text,
            isFinal: true,
            hadFinalBefore: _hadFinalBefore,
            prevPartialLength: _lastPartialLength,
          );
          _notes.selection = TextSelection.collapsed(
            offset: _notes.text.length,
          );
          _hadFinalBefore = true;
          _lastPartialLength = 0; // reset for the next utterance
          _isListening = false;
          _source = 'voice';
        });
      case SpeechErrorEvent(:final reason):
        setState(() {
          _isListening = false;
          _hadFinalBefore = false;
          _lastPartialLength = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice input: $reason')),
        );
      case SpeechStopped():
        setState(() {
          _isListening = false;
          _hadFinalBefore = false;
          _lastPartialLength = 0;
        });
    }
  }

  Future<void> _toggleMic() async {
    final service = ref.read(speechServiceProvider);
    if (_isListening) {
      await service.stop();
      // stop() triggers SpeechFinal on the next event tick.
    } else {
      // New mic session: reset all per-session state so the next partial
      // starts a fresh segment instead of replacing prior dictation.
      setState(() {
        _hadFinalBefore = false;
        _lastPartialLength = 0;
      });
      final localeId = await service.pickDeviceLocaleId();
      await service.startListening(localeId: localeId);
      if (mounted) setState(() => _isListening = true);
    }
  }

  @override
  void dispose() {
    // Cancel any in-flight listen before tearing down the widget.
    ref.read(speechServiceProvider).cancel();
    _speechSub?.cancel();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedConditionId == null) {
      setState(() => _error = 'Pick a condition first');
      return;
    }
    if (_responses.isEmpty) {
      setState(() => _error = 'Log at least one symptom');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _emergencyGuidance = null;
    });
    final res = await ref.read(symptomRepositoryProvider).submit(
          SymptomReportInput(
            responses: Map.unmodifiable(_responses),
            occurredAt: _recall == RecallWindow.past7Days
                ? DateTime.now().subtract(const Duration(days: 3)).toUtc()
                : DateTime.now().toUtc(),
            source: _source,
            recallWindow: _recall,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ),
        );
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        if (value.emergencyGuidance != null) {
          setState(() => _emergencyGuidance = value.emergencyGuidance);
          // Don't auto-close — let the user read the guidance first.
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved. We\'ll sync when you\'re online.')),
          );
          Navigator.of(context).pop();
          context.go('/home');
        }
        break;
      case Err(:final error):
        setState(() => _error = error.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s5, Space.s2, Space.s5, Space.s6,
      ),
      children: [
        Text('How are you feeling?', style: t.textTheme.headlineSmall),
        const SizedBox(height: Space.s2),
        Text(
          'Pick the condition closest to yours, then rate the symptoms you noticed today.',
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s5),
        Text('Condition', style: t.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        _ConditionSelector(
          conditions: widget.snapshot.map((c) => c.condition).toList(),
          selectedId: _selectedConditionId,
          onSelected: (id) => setState(() {
            _selectedConditionId = id;
            _responses.clear();
          }),
        ),
        if (_selectedConditionId != null) ...[
          const SizedBox(height: Space.s6),
          Text('Symptoms', style: t.textTheme.titleSmall),
          const SizedBox(height: Space.s2),
          if (_termsForCondition.isEmpty)
            Text(
              'No symptoms are mapped for this condition yet.',
              style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
            )
          else
            ..._termsForCondition.map(
              (term) => _SymptomRow(
                term: term,
                selectedGrade: _responses[term.id],
                onChanged: (grade) => setState(() {
                  if (grade == null) {
                    _responses.remove(term.id);
                  } else {
                    _responses[term.id] = grade;
                  }
                }),
              ),
            ),
          const SizedBox(height: Space.s6),
          Text('When?', style: t.textTheme.titleSmall),
          const SizedBox(height: Space.s2),
          SegmentedButton<RecallWindow>(
            segments: const [
              ButtonSegment(
                value: RecallWindow.now,
                label: Text('Right now'),
                icon: Icon(Icons.now_widgets_outlined),
              ),
              ButtonSegment(
                value: RecallWindow.past7Days,
                label: Text('Past week'),
                icon: Icon(Icons.history),
              ),
            ],
            selected: {_recall},
            onSelectionChanged: (s) => setState(() => _recall = s.first),
          ),
          const SizedBox(height: Space.s5),
          Text('Logged by', style: t.textTheme.titleSmall),
          const SizedBox(height: Space.s2),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'self', label: Text('Me')),
              ButtonSegment(
                value: 'caregiver',
                label: Text('Caregiver'),
                icon: Icon(Icons.support_agent_outlined),
              ),
              ButtonSegment(
                value: 'voice',
                label: Text('Voice'),
                icon: Icon(Icons.mic_none),
              ),
            ],
            selected: {_source},
            onSelectionChanged: (s) => setState(() => _source = s.first),
          ),
          const SizedBox(height: Space.s6),
          Row(
            children: [
              Text('Notes (optional)', style: t.textTheme.titleSmall),
              const SizedBox(width: Space.s2),
              if (_isListening) const _MicPulseDot(),
            ],
          ),
          const SizedBox(height: Space.s2),
          TextField(
            controller: _notes,
            maxLines: 3,
            maxLength: 4000,
            decoration: InputDecoration(
              hintText: _isListening
                  ? 'Listening — your words appear here'
                  : 'Anything else worth telling your care team',
              suffixIcon: _speechReady
                  ? _MicButton(
                      isListening: _isListening,
                      onTap: _toggleMic,
                    )
                  : null,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: Space.s3),
          Text(
            _error!,
            style: t.textTheme.bodySmall?.copyWith(color: SeverityColors.severe),
          ),
        ],
        if (_emergencyGuidance != null) ...[
          const SizedBox(height: Space.s4),
          _EmergencyGuidanceCard(
            guidance: _emergencyGuidance!,
            onDismiss: () {
              Navigator.of(context).pop();
              context.go('/home');
            },
          ),
        ],
        const SizedBox(height: Space.s5),
        FilledButton(
          onPressed: _busy || _emergencyGuidance != null ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save symptom report'),
        ),
      ],
    );
  }
}

class _ConditionSelector extends StatelessWidget {
  const _ConditionSelector({
    required this.conditions,
    required this.selectedId,
    required this.onSelected,
  });

  final List<VocabCondition> conditions;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (conditions.isEmpty) {
      return Text(
        'No conditions are available yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: Space.s2,
      runSpacing: Space.s2,
      children: [
        for (final c in conditions)
          ChoiceChip(
            label: Text(c.displayName),
            selected: selectedId == c.id,
            onSelected: (_) => onSelected(c.id),
          ),
      ],
    );
  }
}

class _SymptomRow extends StatelessWidget {
  const _SymptomRow({
    required this.term,
    required this.selectedGrade,
    required this.onChanged,
  });

  final VocabSymptomTerm term;
  final int? selectedGrade;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(term.displayName, style: t.textTheme.bodyLarge),
          if (term.plainLanguage != null && term.plainLanguage!.isNotEmpty) ...[
            const SizedBox(height: Space.s1),
            Text(
              term.plainLanguage!,
              style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
            ),
          ],
          const SizedBox(height: Space.s2),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (var g = 0; g < 4; g++)
                _SeverityChoice(
                  grade: g,
                  selected: selectedGrade == g,
                  onTap: () => onChanged(selectedGrade == g ? null : g),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeverityChoice extends StatelessWidget {
  const _SeverityChoice({
    required this.grade,
    required this.selected,
    required this.onTap,
  });

  final int grade;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.all(Space.s1),
        child: SeverityChip(grade: grade, outlined: !selected),
      ),
    );
  }
}

// ── EMERGENCY_GUIDANCE block ────────────────────────────────────────────────
//
// Shown when the server returns a grade-3 alert on a report. The card pulses
// once for 1.2s (BRAND.md motion rule: severe states must attract attention
// without feeling alarming).

class _EmergencyGuidanceCard extends StatefulWidget {
  const _EmergencyGuidanceCard({required this.guidance, required this.onDismiss});
  final String guidance;
  final VoidCallback onDismiss;

  @override
  State<_EmergencyGuidanceCard> createState() => _EmergencyGuidanceCardState();
}

class _EmergencyGuidanceCardState extends State<_EmergencyGuidanceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // 0..1 then back to 1 — single 1.2s pulse per BRAND.md §6.
        final v = _pulse.value;
        final scale = 1.0 + 0.04 * (1 - (v - 0.5).abs() * 2);
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(Space.s4),
        decoration: BoxDecoration(
          color: SeverityColors.severe.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: SeverityColors.severe, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: SeverityColors.severe),
                const SizedBox(width: Space.s2),
                Text(
                  'Severe symptom — read this',
                  style: t.textTheme.titleSmall
                      ?.copyWith(color: SeverityColors.severe),
                ),
              ],
            ),
            const SizedBox(height: Space.s3),
            Text(widget.guidance, style: t.textTheme.bodyMedium),
            const SizedBox(height: Space.s4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDismiss,
                child: const Text('I\'ve read this'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mic button + listening indicator (SYM-05) ──────────────────────────────

class _MicButton extends StatelessWidget {
  const _MicButton({required this.isListening, required this.onTap});
  final bool isListening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isListening ? SeverityColors.severe : Neutrals.slate;
    return IconButton(
      onPressed: onTap,
      tooltip: isListening ? 'Stop dictating' : 'Dictate notes',
      icon: Icon(
        isListening ? Icons.stop_circle_outlined : Icons.mic_none,
        color: color,
      ),
    );
  }
}

/// Tiny animated dot beside the "Notes" label while listening. Sized 8×8
/// so it doesn't compete with the severity pulse; just enough to confirm
/// to the user that the mic is hot.
class _MicPulseDot extends StatefulWidget {
  const _MicPulseDot();

  @override
  State<_MicPulseDot> createState() => _MicPulseDotState();
}

class _MicPulseDotState extends State<_MicPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final v = _ctrl.value; // 0..1..0
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SeverityColors.severe.withValues(
              alpha: 0.55 + 0.45 * v,
            ),
          ),
        );
      },
    );
  }
}