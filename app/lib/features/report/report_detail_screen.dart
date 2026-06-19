// Report detail — print-friendly view of a single symptom_report + its
// responses. RPT-08 attribution: every symptom is paired with its
// PRO-CTCAE term (display_name from symptom_term).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/report_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/severity_chip.dart';

class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({super.key, required this.reportId});
  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: SafeArea(
        child: FutureBuilder<ReportDetail?>(
          future: repo.fetchDetail(reportId),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Couldn\'t load report: ${snap.error}'));
            }
            final detail = snap.data;
            if (detail == null) {
              return const Center(child: Text('Report not found.'));
            }
            return _Body(detail: detail);
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});
  final ReportDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dateFmt = DateFormat('EEEE, MMMM d, y · h:mm a');
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s5, Space.s3, Space.s5, Space.s6,
      ),
      children: [
        Row(
          children: [
            SeverityChip(grade: detail.summary.topGrade),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                dateFmt.format(detail.summary.reportedAt),
                style: t.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        Text(
          _metaLine(detail.summary),
          style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s5),
        Text('Symptoms reported', style: t.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        if (detail.responses.isEmpty)
          Text(
            'No individual symptoms were coded for this report.',
            style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
          )
        else
          ...detail.responses.map((r) => _ResponseRow(response: r)),
        if (detail.freeText != null && detail.freeText!.isNotEmpty) ...[
          const SizedBox(height: Space.s5),
          Text('Notes', style: t.textTheme.titleSmall),
          const SizedBox(height: Space.s2),
          Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: Neutrals.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: Neutrals.mist),
            ),
            child: Text(detail.freeText!, style: t.textTheme.bodyMedium),
          ),
        ],
        const SizedBox(height: Space.s6),
        Container(
          padding: const EdgeInsets.all(Space.s3),
          decoration: BoxDecoration(
            color: Neutrals.mist.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Text(
            'This report is for your own tracking and to share with your care team. '
            'It is not a medical diagnosis.',
            style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
          ),
        ),
      ],
    );
  }

  String _metaLine(ReportSummary s) {
    final parts = <String>['${detail.responses.length} symptom${detail.responses.length == 1 ? '' : 's'}'];
    if (s.recallWindow == 'past_7_days') parts.add('past-week recall');
    if (s.source == 'caregiver') parts.add('logged by caregiver');
    if (s.source == 'voice') parts.add('voice log');
    return parts.join(' · ');
  }
}

class _ResponseRow extends StatelessWidget {
  const _ResponseRow({required this.response});
  final ResponseDetail response;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(
        children: [
          SeverityChip(grade: response.compositeGrade, size: SeverityChipSize.small),
          const SizedBox(width: Space.s3),
          Expanded(child: Text(response.termLabel, style: t.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}