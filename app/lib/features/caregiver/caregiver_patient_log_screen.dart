import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../data/models/condition.dart';
import '../../data/repositories/vocab_repository.dart';
import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../../widgets/severity_scale.dart';

/// SYM-08: Caregiver symptom logging screen for a single patient.
/// Shows the patient's condition symptoms and lets the caregiver log
/// grades on their behalf, submitted via caregiver-submit endpoint.
class CaregiverPatientLogScreen extends ConsumerStatefulWidget {
  const CaregiverPatientLogScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  ConsumerState<CaregiverPatientLogScreen> createState() =>
      _CaregiverPatientLogScreenState();
}

class _CaregiverPatientLogScreenState
    extends ConsumerState<CaregiverPatientLogScreen> {
  final Map<String, int> _responses = {};
  bool _busy = false;
  String? _error;
  String? _success;

  Future<void> _submit() async {
    if (_responses.isEmpty) {
      setState(() => _error = 'Log at least one symptom');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final response = await http
          .post(
            Uri.parse('$apiBase/api/symptoms/caregiver-submit'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'patient_id': widget.patientId,
              'recall_window': 'now',
              'responses': _responses.entries
                  .map((e) => {'pro_ctcae_code': e.key, 'severity': e.value})
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final emergency = body['emergency_guidance'];
        if (emergency is Map<String, dynamic>) {
          _showGuidance(emergency['body'] as String? ?? '');
        } else {
          setState(
            () => _success = 'Symptoms logged for ${widget.patientName}',
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) context.pop();
          });
        }
      } else {
        final msg =
            (jsonDecode(response.body) as Map<String, dynamic>)['error']
                as Map<String, dynamic>? ??
            {};
        setState(
          () => _error = (msg['message'] as String?) ?? 'Submission failed',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showGuidance(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: SeverityColors.severe),
            const SizedBox(width: Space.s2),
            const Text('Attention'),
          ],
        ),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final vocabAsync = ref.watch(vocabSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Log for ${widget.patientName}')),
      body: SafeArea(
        child: vocabAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.s6),
              child: Text(
                'Could not load symptoms: $e',
                style: t.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (snapshot) {
            if (snapshot.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: Text(
                    'No condition information available. Ask your patient to set up their condition in onboarding.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: Neutrals.slate,
                    ),
                  ),
                ),
              );
            }
            final condition = snapshot.first;
            final terms = condition.terms;
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.s5,
                Space.s3,
                Space.s5,
                Space.s10,
              ),
              children: [
                Text(
                  'How is ${widget.patientName} feeling?',
                  style: t.textTheme.headlineSmall,
                ),
                const SizedBox(height: Space.s1),
                Text(
                  'Rate the symptoms you observed. This will be shared with their care team.',
                  style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
                ),
                const SizedBox(height: Space.s6),
                ...terms.map(
                  (term) => Padding(
                    padding: const EdgeInsets.only(bottom: Space.s5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(term.displayName, style: t.textTheme.titleSmall),
                        if (term.plainLanguage != null &&
                            term.plainLanguage!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.s1),
                            child: Text(
                              term.plainLanguage!,
                              style: t.textTheme.bodySmall?.copyWith(
                                color: Neutrals.slate,
                              ),
                            ),
                          ),
                        const SizedBox(height: Space.s2),
                        SeverityScale(
                          grades: const [0, 1, 2, 3],
                          selectedGrade: _responses[term.proCtcaeCode],
                          onChanged: (grade) => setState(() {
                            if (grade == null) {
                              _responses.remove(term.proCtcaeCode);
                            } else {
                              _responses[term.proCtcaeCode] = grade;
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: Text(
                      _error!,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: SeverityColors.severe,
                      ),
                    ),
                  ),
                if (_success != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: SeverityColors.none,
                          size: 18,
                        ),
                        const SizedBox(width: Space.s1),
                        Expanded(
                          child: Text(
                            _success!,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: SeverityColors.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                FilledButton(
                  onPressed: _busy || _success != null ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit symptoms'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
