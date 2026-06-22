import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _weightCtrl = TextEditingController();
  final _bpSysCtrl = TextEditingController();
  final _bpDiaCtrl = TextEditingController();
  final _hrCtrl = TextEditingController();
  final _glucoseCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _bpSysCtrl.dispose();
    _bpDiaCtrl.dispose();
    _hrCtrl.dispose();
    _glucoseCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightCtrl.text);
    final bpSys = int.tryParse(_bpSysCtrl.text);
    final bpDia = int.tryParse(_bpDiaCtrl.text);
    final hr = int.tryParse(_hrCtrl.text);
    final glucose = int.tryParse(_glucoseCtrl.text);
    final notes = _notesCtrl.text.trim();

    if (weight == null &&
        bpSys == null &&
        bpDia == null &&
        hr == null &&
        glucose == null) {
      _showSnack('Enter at least one value.');
      return;
    }

    setState(() => _saving = true);

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) {
        _showSnack('Not signed in.');
        return;
      }

      final body = <String, dynamic>{
        'measured_at': DateTime.now().toUtc().toIso8601String(),
        'notes': notes,
      };
      if (weight != null) body['weight_kg'] = weight;
      if (bpSys != null) body['bp_sys'] = bpSys;
      if (bpDia != null) body['bp_dia'] = bpDia;
      if (hr != null) body['heart_rate'] = hr;
      if (glucose != null) body['glucose_mgdl'] = glucose;

      final response = await http
          .post(
            Uri.parse('$apiBase/api/vitals/manual'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 201) {
        _clearForm();
        _showSnack('Vitals saved!');
      } else {
        final msg =
            (jsonDecode(response.body) as Map<String, dynamic>)['error']
                as String? ??
            'Save failed (${response.statusCode})';
        _showSnack(msg);
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearForm() {
    _weightCtrl.clear();
    _bpSysCtrl.clear();
    _bpDiaCtrl.clear();
    _hrCtrl.clear();
    _glucoseCtrl.clear();
    _notesCtrl.clear();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Log Vitals')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.s5,
            Space.s3,
            Space.s5,
            Space.s10,
          ),
          children: [
            Text(
              'Enter whatever you have — all fields are optional.',
              style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
            ),
            const SizedBox(height: Space.s5),
            _FieldRow(
              icon: Icons.monitor_weight_outlined,
              label: 'Weight',
              suffix: 'kg',
              controller: _weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: Space.s4),
            Text('Blood Pressure', style: t.textTheme.titleSmall),
            const SizedBox(height: Space.s2),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bpSysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Systolic',
                      suffixText: 'mmHg',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: TextField(
                    controller: _bpDiaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Diastolic',
                      suffixText: 'mmHg',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s4),
            _FieldRow(
              icon: Icons.favorite_outline,
              label: 'Heart Rate',
              suffix: 'bpm',
              controller: _hrCtrl,
            ),
            const SizedBox(height: Space.s4),
            _FieldRow(
              icon: Icons.bloodtype_outlined,
              label: 'Blood Glucose',
              suffix: 'mg/dL',
              controller: _glucoseCtrl,
            ),
            const SizedBox(height: Space.s4),
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: Space.s6),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save Vitals'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.suffix,
    required this.controller,
    this.keyboardType,
  });

  final IconData icon;
  final String label;
  final String suffix;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: BrandColors.concordBlue, size: 20),
        const SizedBox(width: Space.s3),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType ?? TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
