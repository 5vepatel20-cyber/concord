import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';

/// Chemo regimen templates (MED-03). Browse, create, and start cyclical
/// chemo schedules that generate treatment_event rows on a calendar.
class ChemoRegimenScreen extends ConsumerStatefulWidget {
  const ChemoRegimenScreen({super.key});

  @override
  ConsumerState<ChemoRegimenScreen> createState() => _ChemoRegimenScreenState();
}

class _ChemoRegimenScreenState extends ConsumerState<ChemoRegimenScreen> {
  List<Regimen> _regimens = [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final res = await http
          .get(
            Uri.parse('$apiBase/api/treatment/regimens'),
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final raw = (body['regimens'] as List<dynamic>?) ?? [];
        setState(() {
          _regimens = raw
              .map((e) => Regimen.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } else {
        setState(() => _error = 'Failed to load (${res.statusCode})');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Chemo regimens')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(),
        icon: const Icon(Icons.add),
        label: const Text('New regimen'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: SeverityColors.severe,
                      ),
                      const SizedBox(height: Space.s3),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: SeverityColors.severe,
                        ),
                      ),
                      const SizedBox(height: Space.s3),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _regimens.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medication, size: 64, color: Neutrals.hint),
                      const SizedBox(height: Space.s3),
                      Text(
                        'No chemo regimens yet.',
                        style: t.textTheme.titleSmall?.copyWith(
                          color: Neutrals.slate,
                        ),
                      ),
                      const SizedBox(height: Space.s1),
                      Text(
                        'Create a regimen template to generate infusion\n'
                        'events on your treatment calendar.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: Neutrals.hint,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.s5,
                  Space.s3,
                  Space.s5,
                  Space.s10,
                ),
                children: _regimens
                    .map(
                      (r) => _RegimenCard(
                        regimen: r,
                        onDelete: () => _deleteRegimen(r.id),
                        onStart: () => _showStartDialog(r),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  Future<void> _deleteRegimen(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete regimen?'),
        content: const Text(
          'This will not delete already-generated calendar events.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: SeverityColors.severe,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      await http
          .delete(
            Uri.parse('$apiBase/api/treatment/regimens/$id'),
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 15));
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showStartDialog(Regimen regimen) async {
    final startDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (startDate == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start regimen'),
        content: Text(
          'Generate ${regimen.totalCycles} cycle events for '
          '"${regimen.name}" starting ${DateFormat.yMMMd().format(startDate)}?\n\n'
          'Events will appear on your treatment calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate events'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final res = await http
          .post(
            Uri.parse('$apiBase/api/treatment/regimens/${regimen.id}/generate'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'start_date': DateFormat('yyyy-MM-dd').format(startDate),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${regimen.totalCycles} cycle events'),
          ),
        );
      } else {
        final msg = (jsonDecode(res.body) as Map<String, dynamic>)['error'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${msg ?? res.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showCreateDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _CreateRegimenDialog(),
    );
    if (result == true && mounted) _load();
  }
}

// ── Regimen card ──────────────────────────────────────────────────────────────

class _RegimenCard extends StatelessWidget {
  const _RegimenCard({
    required this.regimen,
    required this.onDelete,
    required this.onStart,
  });
  final Regimen regimen;
  final VoidCallback onDelete;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Space.s3),
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(Space.s2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B61FF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: const Icon(
                    Icons.medication,
                    color: Color(0xFF7B61FF),
                    size: 24,
                  ),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        regimen.name,
                        style: t.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (regimen.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          regimen.description!,
                          style: t.textTheme.bodySmall?.copyWith(
                            color: Neutrals.slate,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (v) {
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: SeverityColors.severe),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Space.s3),
            Row(
              children: [
                _InfoChip(
                  icon: Icons.repeat,
                  label:
                      '${regimen.cycleLengthDays}d on${regimen.restDays > 0 ? ', ${regimen.restDays}d rest' : ''}',
                ),
                const SizedBox(width: Space.s2),
                _InfoChip(
                  icon: Icons.loop,
                  label: '${regimen.totalCycles} cycles',
                ),
              ],
            ),
            if (regimen.medications.isNotEmpty) ...[
              const SizedBox(height: Space.s2),
              Wrap(
                spacing: Space.s1,
                runSpacing: Space.s1,
                children: regimen.medications
                    .map(
                      (m) => Chip(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          m.medicationName,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: Space.s3),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Start regimen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 2),
      decoration: BoxDecoration(
        color: Neutrals.mist,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Neutrals.slate),
          const SizedBox(width: 4),
          Text(
            label,
            style: t.textTheme.labelSmall?.copyWith(color: Neutrals.slate),
          ),
        ],
      ),
    );
  }
}

// ── Create regimen dialog ─────────────────────────────────────────────────────

class _CreateRegimenDialog extends ConsumerStatefulWidget {
  const _CreateRegimenDialog();

  @override
  ConsumerState<_CreateRegimenDialog> createState() =>
      _CreateRegimenDialogState();
}

class _CreateRegimenDialogState extends ConsumerState<_CreateRegimenDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int _cycleLength = 21;
  int _restDays = 7;
  int _totalCycles = 4;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final body = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'cycle_length_days': _cycleLength,
        'rest_days': _restDays,
        'total_cycles': _totalCycles,
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
      };

      final res = await http
          .post(
            Uri.parse('$apiBase/api/treatment/regimens'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 201) {
        Navigator.of(context).pop(true);
      } else {
        final msg =
            (jsonDecode(res.body) as Map<String, dynamic>)['error']
                as Map<String, dynamic>? ??
            {};
        setState(
          () => _error = (msg['message'] as String?) ?? 'Failed to create',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('New chemo regimen'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Regimen name',
                  hintText: 'e.g. AC-T, R-CHOP, FOLFOX',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: Space.s3),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'e.g. 4 cycles of dose-dense AC followed by T',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: Space.s3),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: 'Cycle length (days)',
                      value: _cycleLength,
                      onChanged: (v) => setState(() => _cycleLength = v),
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: _NumberField(
                      label: 'Rest days',
                      value: _restDays,
                      onChanged: (v) => setState(() => _restDays = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s3),
              _NumberField(
                label: 'Total cycles',
                value: _totalCycles,
                onChanged: (v) => setState(() => _totalCycles = v),
              ),
              const SizedBox(height: Space.s2),
              Text(
                'This regimen will generate ${_totalCycles * (_cycleLength)} '
                'treatment days over ${_totalCycles} cycles.',
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.hint),
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create regimen'),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s1),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
            ),
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class Regimen {
  final String id;
  final String name;
  final String? description;
  final int cycleLengthDays;
  final int restDays;
  final int totalCycles;
  final List<RegimenMedication> medications;

  Regimen({
    required this.id,
    required this.name,
    this.description,
    required this.cycleLengthDays,
    required this.restDays,
    required this.totalCycles,
    required this.medications,
  });

  factory Regimen.fromJson(Map<String, dynamic> j) {
    final meds = (j['medications'] as List<dynamic>? ?? []).map((m) {
      return RegimenMedication.fromJson(m as Map<String, dynamic>);
    }).toList();
    return Regimen(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      description: j['description'] as String?,
      cycleLengthDays: j['cycle_length_days'] as int? ?? 21,
      restDays: j['rest_days'] as int? ?? 0,
      totalCycles: j['total_cycles'] as int? ?? 4,
      medications: meds,
    );
  }
}

class RegimenMedication {
  final String medicationName;
  final String? rxnormCui;
  final String? dose;
  final String? unit;
  final String? route;

  RegimenMedication({
    required this.medicationName,
    this.rxnormCui,
    this.dose,
    this.unit,
    this.route,
  });

  factory RegimenMedication.fromJson(Map<String, dynamic> j) {
    return RegimenMedication(
      medicationName: j['medication_name'] as String? ?? '',
      rxnormCui: j['rxnorm_cui'] as String?,
      dose: j['dose'] as String?,
      unit: j['unit'] as String?,
      route: j['route'] as String?,
    );
  }
}
