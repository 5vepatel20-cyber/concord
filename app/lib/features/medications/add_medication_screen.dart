// Add-medication screen (MED-01, MED-02, MED-03).
//
// Features RxNorm-powered autocomplete on the medication name field
// (MED-01). The backend proxies the NIH RxNav API so the client never
// talks to an external domain. Free-text is still allowed if the user
// doesn't pick from the suggestions.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/notifications/medication_reminder_service.dart';
import '../../core/result/result.dart';
import '../../data/models/medication.dart';
import '../../data/repositories/medication_repository.dart';
import '../../data/supabase/supabase_provider.dart';
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
  final _nameFocus = FocusNode();

  MedRoute _route = MedRoute.oral;
  MedFrequency _frequency = MedFrequency.daily;
  final List<TimeOfDay> _times = const [];
  final Set<Weekday> _days = {};
  bool _busy = false;
  String? _error;

  // RxNorm autocomplete state.
  String? _rxcui;
  List<RxNormSuggestion> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;
  final _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.removeListener(_onNameChanged);
    _name.dispose();
    _nameFocus.dispose();
    _dose.dispose();
    _unit.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    _debounce?.cancel();
    // Clear the selected rxcui any time the user edits the text manually.
    _rxcui = null;
    final query = _name.text.trim();
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final response = await http
          .post(
            Uri.parse('$apiBase/api/medications/rxnorm/search'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({'query': query, 'maxResults': 10}),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = (body['results'] as List<dynamic>?) ?? [];
        setState(() {
          _suggestions = raw
              .map((s) => RxNormSuggestion.fromJson(s as Map<String, dynamic>))
              .toList();
        });
      } else {
        setState(() => _suggestions = []);
      }
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSuggestion(RxNormSuggestion s) {
    _name.text = s.name;
    _name.selection = TextSelection.fromPosition(
      TextPosition(offset: s.name.length),
    );
    _rxcui = s.rxcui;
    setState(() => _suggestions = []);
    _nameFocus.unfocus();
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
      rxnormCode: _rxcui,
    );
    final res = await ref.read(medicationRepositoryProvider).create(draft);
    if (!mounted) return;
    switch (res) {
      case Ok():
        () async {
          final reminder = ref.read(medicationReminderServiceProvider);
          await reminder.ensurePermission();
          await reminder.scheduleFor(draft);
        }();
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
              Space.s5,
              Space.s3,
              Space.s5,
              Space.s6,
            ),
            children: [
              CompositedTransformTarget(
                link: _layerLink,
                child: TextFormField(
                  controller: _name,
                  focusNode: _nameFocus,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Tamoxifen',
                    suffixIcon: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : (_rxcui != null
                              ? const Icon(
                                  Icons.check_circle,
                                  color: SeverityColors.none,
                                  size: 20,
                                )
                              : null),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  onTap: () {
                    // Re-show suggestions if the user taps back in.
                    final q = _name.text.trim();
                    if (q.length >= 2) _search(q);
                  },
                ),
              ),
              if (_suggestions.isNotEmpty)
                CompositedTransformFollower(
                  link: _layerLink,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 4),
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: Neutrals.hairline),
                        itemBuilder: (ctx, i) {
                          final s = _suggestions[i];
                          return InkWell(
                            onTap: () => _selectSuggestion(s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.s4,
                                vertical: Space.s3,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: t.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        if (s.synonym != null &&
                                            s.synonym != s.name)
                                          Text(
                                            s.synonym!,
                                            style: t.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: Neutrals.slate,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (s.tty != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: Space.s1,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: BrandColors.concordBlueTint,
                                        borderRadius: BorderRadius.circular(
                                          Radii.sm,
                                        ),
                                      ),
                                      child: Text(
                                        s.tty!,
                                        style: t.textTheme.labelSmall?.copyWith(
                                          color: BrandColors.concordBlue,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
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
                onSelectionChanged: (s) => setState(() => _frequency = s.first),
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
                      onPressed: _times.isEmpty ? _pickTime : _addAnotherTime,
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
                          onDeleted: () => setState(() => _times.remove(t)),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(
                          _times.isEmpty ? 'Add a time' : 'Add another',
                        ),
                        onPressed: _times.isEmpty ? _pickTime : _addAnotherTime,
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
                  style: t.textTheme.bodySmall?.copyWith(
                    color: SeverityColors.severe,
                  ),
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

class RxNormSuggestion {
  final String rxcui;
  final String name;
  final String? synonym;
  final String? tty;

  RxNormSuggestion({
    required this.rxcui,
    required this.name,
    this.synonym,
    this.tty,
  });

  factory RxNormSuggestion.fromJson(Map<String, dynamic> j) => RxNormSuggestion(
    rxcui: j['rxcui'] as String? ?? '',
    name: j['name'] as String? ?? '',
    synonym: j['synonym'] as String?,
    tty: j['tty'] as String?,
  );
}
