import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/alert_repository.dart';
import '../../theme/tokens.dart';

/// Escalation policy settings (ALRT-06). Configure how alerts are routed
/// based on severity, time of day, and target role.
class EscalationPolicyScreen extends ConsumerStatefulWidget {
  const EscalationPolicyScreen({super.key});

  @override
  ConsumerState<EscalationPolicyScreen> createState() =>
      _EscalationPolicyScreenState();
}

class _EscalationPolicyScreenState
    extends ConsumerState<EscalationPolicyScreen> {
  List<EscalationPolicy> _policies = [];
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
      final policies = await ref.read(alertRepositoryProvider).fetchPolicies();
      if (!mounted) return;
      setState(() => _policies = policies);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deletePolicy(String id) async {
    try {
      await ref.read(alertRepositoryProvider).deletePolicy(id);
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Escalation policies')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add policy'),
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
            : _policies.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.policy_outlined,
                        size: 64,
                        color: Neutrals.hint,
                      ),
                      const SizedBox(height: Space.s3),
                      Text(
                        'No escalation policies.',
                        style: t.textTheme.titleSmall?.copyWith(
                          color: Neutrals.slate,
                        ),
                      ),
                      const SizedBox(height: Space.s1),
                      Text(
                        'Add policies to control how symptom alerts\n'
                        'are routed based on severity and time of day.',
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
                children: [
                  Text(
                    'Policies are evaluated in priority order. '
                    'The first matching policy determines routing.',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.hint,
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  ..._policies.map(
                    (p) => _PolicyCard(
                      policy: p,
                      onDelete: () {
                        showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete policy?'),
                            content: Text('Delete "${p.name}"?'),
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
                        ).then((ok) {
                          if (ok == true) _deletePolicy(p.id);
                        });
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _AddPolicyDialog(),
    );
    if (result == true && mounted) _load();
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.policy, required this.onDelete});
  final EscalationPolicy policy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final severityColor = switch (policy.severityThreshold) {
      'emergency' => SeverityColors.severe,
      'urgent' => const Color(0xFFE67E22),
      _ => Neutrals.slate,
    };

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
                    color: severityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Icon(Icons.policy, color: severityColor, size: 24),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        policy.name,
                        style: t.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Priority ${policy.priority}',
                        style: t.textTheme.labelSmall?.copyWith(
                          color: Neutrals.hint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!policy.active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.s2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Neutrals.hint.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      'Inactive',
                      style: t.textTheme.labelSmall?.copyWith(
                        color: Neutrals.hint,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: Space.s2),
            Row(
              children: [
                _InfoBadge(
                  label: policy.severityThreshold,
                  color: severityColor,
                ),
                const SizedBox(width: Space.s1),
                _InfoBadge(
                  label: policy.timeRestriction.replaceAll('_', ' '),
                  color: BrandColors.concordBlue,
                ),
              ],
            ),
            const SizedBox(height: Space.s1),
            Row(
              children: [
                _InfoBadge(
                  label: '→ ${policy.targetRole}',
                  color: Neutrals.slate,
                ),
                const SizedBox(width: Space.s1),
                _InfoBadge(
                  label: 'via ${policy.notificationChannel}',
                  color: Neutrals.slate,
                ),
                if (policy.delayMinutes > 0) ...[
                  const SizedBox(width: Space.s1),
                  _InfoBadge(
                    label: '${policy.delayMinutes}min delay',
                    color: Neutrals.slate,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _AddPolicyDialog extends ConsumerStatefulWidget {
  const _AddPolicyDialog();

  @override
  ConsumerState<_AddPolicyDialog> createState() => _AddPolicyDialogState();
}

class _AddPolicyDialogState extends ConsumerState<_AddPolicyDialog> {
  final _nameCtrl = TextEditingController(text: 'Default');
  String _severity = 'urgent';
  String _timeRestriction = 'always';
  String _targetRole = 'caregiver';
  String _channel = 'email';
  int _priority = 0;
  int _delay = 0;
  bool _active = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(alertRepositoryProvider).createPolicy({
        'name': _nameCtrl.text.trim(),
        'severity_threshold': _severity,
        'time_restriction': _timeRestriction,
        'target_role': _targetRole,
        'notification_channel': _channel,
        'priority': _priority,
        'delay_minutes': _delay,
        'active': _active,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add escalation policy'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Policy name'),
            ),
            const SizedBox(height: Space.s3),
            DropdownButtonFormField<String>(
              value: _severity,
              decoration: const InputDecoration(labelText: 'Minimum severity'),
              items: const [
                DropdownMenuItem(value: 'info', child: Text('Info')),
                DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                DropdownMenuItem(value: 'emergency', child: Text('Emergency')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _severity = v);
              },
            ),
            const SizedBox(height: Space.s3),
            DropdownButtonFormField<String>(
              value: _timeRestriction,
              decoration: const InputDecoration(labelText: 'Time restriction'),
              items: const [
                DropdownMenuItem(value: 'always', child: Text('Always')),
                DropdownMenuItem(
                  value: 'business_hours',
                  child: Text('Business hours (Mon-Fri 8-18)'),
                ),
                DropdownMenuItem(
                  value: 'after_hours',
                  child: Text('After hours & weekends'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _timeRestriction = v);
              },
            ),
            const SizedBox(height: Space.s3),
            DropdownButtonFormField<String>(
              value: _targetRole,
              decoration: const InputDecoration(labelText: 'Notify'),
              items: const [
                DropdownMenuItem(value: 'caregiver', child: Text('Caregivers')),
                DropdownMenuItem(value: 'clinician', child: Text('Clinicians')),
                DropdownMenuItem(value: 'both', child: Text('Both')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _targetRole = v);
              },
            ),
            const SizedBox(height: Space.s3),
            DropdownButtonFormField<String>(
              value: _channel,
              decoration: const InputDecoration(
                labelText: 'Notification channel',
              ),
              items: const [
                DropdownMenuItem(value: 'email', child: Text('Email')),
                DropdownMenuItem(
                  value: 'push',
                  child: Text('Push (coming soon)'),
                ),
                DropdownMenuItem(
                  value: 'sms',
                  child: Text('SMS (coming soon)'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _channel = v);
              },
            ),
            const SizedBox(height: Space.s3),
            Row(
              children: [
                Expanded(
                  child: _StepperField(
                    label: 'Priority',
                    value: _priority,
                    onChanged: (v) => setState(() => _priority = v),
                  ),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: _StepperField(
                    label: 'Delay (min)',
                    value: _delay,
                    onChanged: (v) => setState(() => _delay = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s3),
            SwitchListTile(
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.s2),
              Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: SeverityColors.severe),
              ),
            ],
          ],
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
              : const Text('Add policy'),
        ),
      ],
    );
  }
}

class _StepperField extends StatelessWidget {
  const _StepperField({
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
              onPressed: value > 0 ? () => onChanged(value - 1) : null,
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
