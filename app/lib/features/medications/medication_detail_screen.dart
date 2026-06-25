import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models/medication.dart';
import '../../data/repositories/medication_repository.dart';
import '../../theme/tokens.dart';
import 'medications_screen.dart';

class MedicationDetailScreen extends ConsumerWidget {
  const MedicationDetailScreen({super.key, required this.medicationId});
  final String medicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medsAsync = ref.watch(medicationsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Medication details')),
      body: SafeArea(
        child: medsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (meds) {
            final med = meds.where((m) => m.id == medicationId).firstOrNull;
            if (med == null) {
              return const Center(child: Text('Medication not found'));
            }
            return _Body(medication: med);
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.medication});
  final Medication medication;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _deactivating = false;

  Future<void> _confirmDeactivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate medication?'),
        content: Text(
          'Stop tracking "${widget.medication.displayName}"? '
          'You can always add it again later.',
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
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deactivating = true);
    final repo = ref.read(medicationRepositoryProvider);
    final id = widget.medication.id;
    if (id == null) return;

    final result = await repo.deactivate(id);
    if (!mounted) return;

    setState(() => _deactivating = false);

    result.when(
      ok: (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Medication deactivated')));
        context.pop();
      },
      err: (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not deactivate: ${e.message}')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final m = widget.medication;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s3,
        Space.s5,
        Space.s6,
      ),
      children: [
        // Name + status
        Row(
          children: [
            Icon(Icons.medication_outlined, color: BrandColors.concordBlue),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.displayName, style: t.textTheme.titleLarge),
                  if (m.rxnormCode != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'RxNorm: ${m.rxnormCode}',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: Neutrals.hint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: m.active
                    ? SeverityColors.none.withValues(alpha: 0.12)
                    : Neutrals.mist,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                m.active ? 'Active' : 'Inactive',
                style: t.textTheme.bodySmall?.copyWith(
                  color: m.active ? SeverityColors.none : Neutrals.slate,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s5),
        _InfoRow(
          label: 'Dose',
          value: m.dose != null ? '${m.dose} ${m.unit ?? ""}' : '—',
        ),
        _InfoRow(label: 'Route', value: m.route.displayName),
        _InfoRow(label: 'Schedule', value: m.summary),
        if (m.createdAt != null)
          _InfoRow(
            label: 'Added',
            value: DateFormat('MMM d, yyyy').format(m.createdAt!),
          ),
        const SizedBox(height: Space.s6),
        // Adherence summary
        Text('Recent adherence', style: t.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        _RecentAdherenceCard(medicationId: m.id),

        const SizedBox(height: Space.s6),
        // Actions
        if (m.active)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _deactivating ? null : _confirmDeactivate,
              icon: _deactivating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text(_deactivating ? 'Deactivating…' : 'Deactivate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SeverityColors.severe,
                side: BorderSide(
                  color: SeverityColors.severe.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
            ),
          ),
          Expanded(child: Text(value, style: t.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _RecentAdherenceCard extends ConsumerWidget {
  const _RecentAdherenceCard({required this.medicationId});
  final String? medicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final medsAsync = ref.watch(medicationsListProvider);

    return medsAsync.when(
      loading: () => const Card(
        child: SizedBox(height: 48, child: Center(child: Text('Loading…'))),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (_) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adherence data is available on the dashboard.',
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
              ),
              const SizedBox(height: Space.s2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.push('/medications/adherence'),
                  icon: const Icon(Icons.bar_chart_outlined, size: 18),
                  label: const Text('View dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
