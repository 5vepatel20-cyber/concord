// Add-medication screen (MED-02, MED-03).
//
// Simple structured form. For 1.1 we keep this manual (no RxNorm
// autocomplete — that's a follow-up that needs an external API). The
// fields map 1:1 to the medication.schedule JSONB on the backend.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../data/models/medication.dart';
import '../../data/repositories/medication_repository.dart';
import '../../theme/tokens.dart';
import 'medications_screen.dart';

class AddMedicationScreen extends ConsumerStatefulWidget {
  const AddMedicationScreen({super.key});

  @override
  ConsumerState<AddMedicationScreen> createState() =>
      _AddMedicationScreenState();
}

class _AddMedicationScreenState extends ConsumerState<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _unit = TextEditingController();
  final _notes = TextEditingController();

  MedRoute _route = MedRoute.oral;
  MedFrequency _frequency = MedFrequency.daily;
  final List<TimeOfDay> _times = const [];
  final Set<Weekday> _days = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _unit.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_frequency == MedFrequency.daily && _times.isEmpty) {
      setState(() => _error = 'Add at least one dose time');
      return;
    }
    if (_frequency == MedFrequency.weekly && _days.isEmpty) {
      setState(() => _error = 'Pick at least one day');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final schedule = MedSchedule(
      frequency: _frequency,
      times: _times.map(_formatTime).toList(),
      days: _days.toList(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final draft = Medication(
      id: null,
      displayName: _name.text.trim(),
      dose: _dose.text.trim().isEmpty ? null : _dose.text.trim(),
      unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      route: _route,
      schedule: schedule,
    );
    final res = await ref.read(medicationRepositoryProvider).create(draft);
    if (!mounted) return;
    switch (res) {
      case Ok():
        // Refresh the list so the new med shows up immediately.
        // ignore: discarded_futures
        ref.read(medicationsListProvider.notifier).refresh();
        context.pop();
      case Err(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() {
        _times
          ..clear()
          ..add(picked);
      });
    }
  }

  Future<void> _addAnotherTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times.isNotEmpty
          ? _times.last
          : const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _times.add(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add medication')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.s5, Space.s3, Space.s5, Space.s6,
            ),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Tamoxifen',
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Required'
                    : null,
              ),
              const SizedBox(height: Space.s4),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _dose,
                      decoration: const InputDecoration(
                        labelText: 'Dose',
                        hintText: 'e.g. 20',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        hintText: 'e.g. mg, mL',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s4),
              Text('Route', style: t.textTheme.titleSmall),
              const SizedBox(height: Space.s2),
              Wrap(
                spacing: Space.s2,
                children: MedRoute.values.map((r) {
                  final selected = _route == r;
                  return ChoiceChip(
                    label: Text(r.displayName),
                    selected: selected,
                    onSelected: (_) => setState(() => _route = r),
                  );
                }).toList(),
              ),
              const SizedBox(height: Space.s4),
              Text('Frequency', style: t.textTheme.titleSmall),
              const SizedBox(height: Space.s2),
              SegmentedButton<MedFrequency>(
                segments: const [
                  ButtonSegment(
                    value: MedFrequency.daily,
                    label: Text('Daily'),
                    icon: Icon(Icons.today),
                  ),
                  ButtonSegment(
                    value: MedFrequency.weekly,
                    label: Text('Weekly'),
                    icon: Icon(Icons.calendar_view_week),
                  ),
                  ButtonSegment(
                    value: MedFrequency.asNeeded,
                    label: Text('As needed'),
                    icon: Icon(Icons.help_outline),
                  ),
                ],
                selected: {_frequency},
                onSelectionChanged: (s) =>
                    setState(() => _frequency = s.first),
              ),
              if (_frequency == MedFrequency.daily) ...[
                const SizedBox(height: Space.s4),
                Text('Times', style: t.textTheme.titleSmall),
                const SizedBox(height: Space.s2),
                Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: [
                    for (final t in _times)
                      InputChip(
                        label: Text(_formatTime(t)),
                        onDeleted: () => setState(() => _times.remove(t)),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(
                        _times.isEmpty ? 'Add a time' : 'Add another',
                      ),
                      onPressed:
                          _times.isEmpty ? _pickTime : _addAnotherTime,
                    ),
                  ],
                ),
              ],
              if (_frequency == MedFrequency.weekly) ...[
                const SizedBox(height: Space.s4),
                Text('Days', style: t.textTheme.titleSmall),
                const SizedBox(height: Space.s2),
                Wrap(
                  spacing: Space.s2,
                  children: Weekday.values.map((d) {
                    final selected = _days.contains(d);
                    return FilterChip(
                      label: Text(d.shortName),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _days.add(d);
                        } else {
                          _days.remove(d);
                        }
                      }),
                    );
                  }).toList(),
                ),
                if (_days.isNotEmpty) ...[
                  const SizedBox(height: Space.s4),
                  Text('Times', style: t.textTheme.titleSmall),
                  const SizedBox(height: Space.s2),
                  Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s2,
                    children: [
                      for (final t in _times)
                        InputChip(
                          label: Text(_formatTime(t)),
                          onDeleted: () =>
                              setState(() => _times.remove(t)),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(
                          _times.isEmpty ? 'Add a time' : 'Add another',
                        ),
                        onPressed:
                            _times.isEmpty ? _pickTime : _addAnotherTime,
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: Space.s4),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'e.g. take with food',
                ),
                maxLines: 2,
                maxLength: 500,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.s2),
                Text(
                  _error!,
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: SeverityColors.severe),
                ),
              ],
              const SizedBox(height: Space.s5),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save medication'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
