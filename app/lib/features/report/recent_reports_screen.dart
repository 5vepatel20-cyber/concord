// Recent reports — list grouped by week. Top of the list is the most recent.
// Tapping a row pushes to the detail view.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/report_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/severity_chip.dart';

class RecentReportsScreen extends ConsumerWidget {
  const RecentReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/report/generate'),
            icon: const Icon(Icons.summarize_outlined, size: 18),
            label: const Text('Summary'),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<ReportSummary>>(
          future: repo.listRecent(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Text('Couldn\'t load reports: ${snap.error}'),
              );
            }
            final reports = snap.data ?? const [];
            if (reports.isEmpty) {
              return const _EmptyState();
            }
            final grouped = groupByWeek(reports);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                Space.s5,
                Space.s3,
                Space.s5,
                Space.s6,
              ),
              itemCount: grouped.length,
              itemBuilder: (context, i) {
                final weekStart = grouped.keys.elementAt(i);
                final weekReports = grouped[weekStart]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s3),
                      child: Text(
                        weekLabel(weekStart),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ...weekReports.map((r) => _ReportTile(report: r)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 48, color: Neutrals.slate),
            const SizedBox(height: Space.s3),
            Text('No reports yet', style: t.textTheme.titleMedium),
            const SizedBox(height: Space.s2),
            Text(
              'Once you log a symptom, it shows up here grouped by week.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});
  final ReportSummary report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final timeFmt = DateFormat('MMM d · h:mm a');
    return Card(
      margin: const EdgeInsets.only(bottom: Space.s2),
      child: InkWell(
        onTap: () => context.push('/report/${report.id}'),
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Row(
            children: [
              SeverityChip(grade: report.topGrade),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeFmt.format(report.reportedAt),
                      style: t.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: Space.s1),
                    Text(
                      _subtitle(report),
                      style: t.textTheme.bodySmall?.copyWith(
                        color: Neutrals.slate,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Neutrals.slate),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(ReportSummary r) {
    final parts = <String>[];
    if (r.recallWindow == 'past_7_days') parts.add('past week');
    if (r.source == 'caregiver') parts.add('caregiver');
    if (r.source == 'voice') parts.add('voice');
    return parts.isEmpty ? 'logged now' : parts.join(' · ');
  }
}
