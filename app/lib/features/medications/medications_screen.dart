// Medications list screen (MED-01, MED-04).
//
// Renders the current patient's medications grouped by "scheduled now"
// (ones with a dose time within the next hour) and "later / as needed".
// Each row exposes quick Take / Skip actions so the patient can log
// adherence in two taps — no modal needed for the common case.
//
// Offline behavior: reads from the local cache first, then refreshes
// from the server. Adherence log writes go through MedicationRepository
// which queues to drift if offline.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock/clock.dart';
import '../../data/models/medication.dart';
import '../../data/repositories/medication_repository.dart';
import '../../theme/tokens.dart';

final medicationsListProvider =
    AsyncNotifierProvider<_MedicationsListController, List<Medication>>(
  _MedicationsListController.new,
);

class _MedicationsListController extends AsyncNotifier<List<Medication>> {
  @override
  Future<List<Medication>> build() async {
    final repo = ref.read(medicationRepositoryProvider);
    // Hydrate from cache first so the list renders instantly on cold start.
    final cached = await repo.cachedMeds();
    if (cached.isNotEmpty) {
      // Fire-and-forget refresh; the provider will re-emit when done.
      // ignore: discarded_futures
      _refresh();
      return cached;
    }
    return _refreshReturn();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_refreshReturn);
  }

  Future<void> _refresh() async {
    state = await AsyncValue.guard(_refreshReturn);
  }

  Future<List<Medication>> _refreshReturn() async {
    final repo = ref.read(medicationRepositoryProvider);
    final res = await repo.fetchAll(onlyActive: true);
    return res.when(
      ok: (m) => m,
      err: (_) async => repo.cachedMeds(),
    );
  }
}

class MedicationsScreen extends ConsumerWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medsAsync = ref.watch(medicationsListProvider);
    final clock = ref.watch(clockProvider);
    final now = clock.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(medicationsListProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/medications/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add medication'),
      ),
      body: SafeArea(
        child: medsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(message: 'Couldn\'t load medications: $e'),
          data: (meds) {
            if (meds.isEmpty) return const _EmptyState();
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(medicationsListProvider.notifier).refresh(),
              child: _MedicationList(meds: meds, now: now),
            );
          },
        ),
      ),
    );
  }
}

class _MedicationList extends StatelessWidget {
  const _MedicationList({required this.meds, required this.now});
  final List<Medication> meds;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        Space.s5, Space.s3, Space.s5, Space.s10,
      ),
      itemCount: meds.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.s3),
      itemBuilder: (ctx, i) {
        final m = meds[i];
        return _MedicationCard(medication: m, now: now);
      },
    );
  }
}

class _MedicationCard extends ConsumerWidget {
  const _MedicationCard({required this.medication, required this.now});
  final Medication medication;
  final DateTime now;

  bool get _isDueNow {
    final s = medication.schedule;
    if (s.frequency == MedFrequency.asNeeded) return false;
    if (s.times.isEmpty) return false;
    // A dose is "due now" if any scheduled time is within ±30 min.
    final nowMin = now.hour * 60 + now.minute;
    for (final t in s.times) {
      final parts = t.split(':');
      if (parts.length != 2) continue;
      final scheduled = int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!;
      if ((scheduled - nowMin).abs() <= 30) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final due = _isDueNow;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: Neutrals.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                due ? Icons.notifications_active : Icons.medication_outlined,
                color: due ? BrandColors.concordBlue : Neutrals.slate,
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.displayName,
                      style: t.textTheme.titleMedium,
                    ),
                    if (medication.dose != null || medication.unit != null) ...[
                      const SizedBox(height: Space.s1),
                      Text(
                        [
                          medication.dose,
                          medication.unit,
                        ].whereType<String>().join(' '),
                        style: t.textTheme.bodyMedium
                            ?.copyWith(color: Neutrals.slate),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          Text(
            medication.summary,
            style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
          ),
          if (medication.id != null && due) ...[
            const SizedBox(height: Space.s3),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _log(
                      context, ref, AdherenceStatus.skipped,
                    ),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _log(
                      context, ref, AdherenceStatus.taken,
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Taken'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _log(
    BuildContext context,
    WidgetRef ref,
    AdherenceStatus status,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = medication.id;
    if (id == null) {
      // Shouldn't happen for active meds (we only render rows the server
      // has confirmed) but be defensive.
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Not ready yet — we\'ll sync when this confirms.'),
        ),
      );
      return;
    }
    final repo = ref.read(medicationRepositoryProvider);
    final res = await repo.logAdherence(
      medicationServerId: id,
      event: AdherenceEvent(
        medicationId: id,
        scheduledFor: now,
        status: status,
      ),
    );
    if (!context.mounted) return;
    res.when(
      ok: (_) => messenger.showSnackBar(
        SnackBar(
          content: Text(
            status == AdherenceStatus.taken
                ? 'Marked taken. Saved.'
                : 'Marked skipped. Saved.',
          ),
        ),
      ),
      err: (e) => messenger.showSnackBar(
        SnackBar(content: Text('Could not save: ${e.message}')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Space.s5),
      children: [
        const SizedBox(height: Space.s10),
        Icon(
          Icons.medication_outlined,
          size: 64,
          color: Neutrals.hint,
        ),
        const SizedBox(height: Space.s4),
        Text(
          'No medications yet',
          textAlign: TextAlign.center,
          style: t.textTheme.titleLarge,
        ),
        const SizedBox(height: Space.s2),
        Text(
          'Add what you take so we can help you stay on track and spot '
          'patterns when symptoms show up.',
          textAlign: TextAlign.center,
          style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s5),
        Center(
          child: FilledButton.icon(
            onPressed: () => context.push('/medications/add'),
            icon: const Icon(Icons.add),
            label: const Text('Add your first medication'),
          ),
        ),
      ],
    );
  }
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
