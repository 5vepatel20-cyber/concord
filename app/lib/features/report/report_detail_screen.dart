// Report detail — print-friendly view of a single symptom_report + its
// responses. RPT-08 attribution: every symptom is paired with its
// PRO-CTCAE term (display_name from symptom_term).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/report_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/severity_chip.dart';

class ReportDetailScreen extends ConsumerStatefulWidget {
  const ReportDetailScreen({super.key, required this.reportId});
  final String reportId;

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final url = await ref
          .read(reportRepositoryProvider)
          .shareReport(widget.reportId);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Share link copied to clipboard')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Share failed: $e'),
          backgroundColor: SeverityColors.severe,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(reportRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          IconButton(
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: _sharing ? null : _share,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<ReportDetail?>(
          future: repo.fetchDetail(widget.reportId),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Text('Couldn\'t load report: ${snap.error}'),
              );
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
        Space.s5,
        Space.s3,
        Space.s5,
        Space.s6,
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
    final parts = <String>[
      '${detail.responses.length} symptom${detail.responses.length == 1 ? '' : 's'}',
    ];
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
    final attr = response.attributionLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SeverityChip(
              grade: response.compositeGrade,
              size: SeverityChipSize.small,
            ),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(response.termLabel, style: t.textTheme.bodyMedium),
                if (attr != 'Presence only' && attr != 'All attributes normal')
                  Text(
                    attr,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.slate,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          if (attr == 'Presence only')
            Text(
              attr,
              style: t.textTheme.bodySmall?.copyWith(
                color: Neutrals.slate,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
