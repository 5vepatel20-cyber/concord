import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/models/condition.dart';
import '../../data/repositories/vocab_repository.dart';
import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../symptoms/quick_log_screen.dart';

/// Inline quick-log widget for the home screen (SYM-10).
/// Shows the patient's condition symptoms as compact SeverityScale rows.
/// One-tap to log — no bottom sheet needed for a single symptom.
class QuickLogWidget extends ConsumerStatefulWidget {
  const QuickLogWidget({super.key});

  @override
  ConsumerState<QuickLogWidget> createState() => _QuickLogWidgetState();
}

class _QuickLogWidgetState extends ConsumerState<QuickLogWidget> {
  final Map<String, int> _selected = {};
  bool _saving = false;
  String? _error;
  String? _success;

  Future<void> _logSingle(String code, int grade) async {
    if (_saving) return;
    setState(() {
      _selected[code] = grade;
      _saving = true;
      _error = null;
      _success = null;
    });

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final response = await http
          .post(
            Uri.parse('$apiBase/api/symptoms/quick'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'responses': [
                {'pro_ctcae_code': code, 'grade': grade},
              ],
              'recall_window': 'now',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final emergency = body['emergency_guidance'];
        if (emergency is Map<String, dynamic>) {
          final msg = emergency['body'] as String? ?? 'Guidance available';
          _showGuidance(msg);
        } else {
          setState(() {
            _success = 'Logged!';
            _selected.remove(code);
          });
          _clearSuccessAfter();
        }
      } else {
        setState(() => _error = 'Failed (${response.statusCode})');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
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

  void _clearSuccessAfter() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _success = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final vocabAsync = ref.watch(vocabSnapshotProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(Space.s1),
                  decoration: BoxDecoration(
                    color: BrandColors.concordBlueTint,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Icon(
                    Icons.add_circle_outline,
                    color: BrandColors.concordBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: Space.s2),
                Text('Quick Log', style: t.textTheme.titleSmall),
                const Spacer(),
                if (_success != null)
                  Text(
                    _success!,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: SeverityColors.none,
                    ),
                  ),
                if (_saving)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: Space.s3),
            vocabAsync.when(
              loading: () => const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Text(
                'Could not load symptoms',
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
              ),
              data: (snapshot) {
                if (snapshot.isEmpty) {
                  return Text(
                    'Set up your condition in onboarding',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.slate,
                    ),
                  );
                }
                final condition = snapshot.first;
                final terms = condition.terms.take(4).toList();
                return Column(
                  children: terms.map((term) {
                    final selected = _selected[term.proCtcaeCode];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Space.s3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(term.displayName, style: t.textTheme.bodyMedium),
                          const SizedBox(height: Space.s1),
                          Row(
                            children: [0, 1, 2, 3].map((g) {
                              final isSelected = selected == g;
                              final color = SeverityColors.byGrade(g);
                              return Padding(
                                padding: const EdgeInsets.only(right: Space.s2),
                                child: InkWell(
                                  onTap: _saving
                                      ? null
                                      : () => _logSingle(term.proCtcaeCode, g),
                                  borderRadius: BorderRadius.circular(Radii.sm),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Space.s2,
                                      vertical: Space.s1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? color.withValues(alpha: 0.15)
                                          : null,
                                      borderRadius: BorderRadius.circular(
                                        Radii.sm,
                                      ),
                                      border: Border.all(
                                        color: isSelected
                                            ? color
                                            : Neutrals.hairline,
                                      ),
                                    ),
                                    child: Text(
                                      SeverityColors.labelByGrade(g),
                                      style: t.textTheme.labelSmall?.copyWith(
                                        color: isSelected
                                            ? color
                                            : Neutrals.slate,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Text(
                  _error!,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: SeverityColors.severe,
                  ),
                ),
              ),
            const SizedBox(height: Space.s2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => QuickLogScreen.show(context),
                icon: const Icon(Icons.list, size: 16),
                label: const Text('Full log'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
