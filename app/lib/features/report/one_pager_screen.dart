import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/report_repository.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class OnePagerScreen extends ConsumerStatefulWidget {
  const OnePagerScreen({super.key, this.days = 14});

  final int days;

  @override
  ConsumerState<OnePagerScreen> createState() => _OnePagerScreenState();
}

class _OnePagerScreenState extends ConsumerState<OnePagerScreen> {
  Future<OnePagerReport>? _future;

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(reportRepositoryProvider)
        .generateOnePager(days: widget.days);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Symptom Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Regenerate',
            onPressed: () {
              setState(() {
                _future = ref
                    .read(reportRepositoryProvider)
                    .generateOnePager(days: widget.days);
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<OnePagerReport>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
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
                        'Could not generate report',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: Space.s2),
                      Text(
                        '${snap.error}',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Neutrals.slate),
                      ),
                      const SizedBox(height: Space.s4),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _future = ref
                                .read(reportRepositoryProvider)
                                .generateOnePager(days: widget.days);
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final report = snap.data;
            if (report == null) {
              return const Center(child: Text('No data'));
            }
            return _Body(report: report);
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.report});
  final OnePagerReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s2,
        Space.s5,
        Space.s10,
      ),
      children: [
        _Header(report: report),
        const SizedBox(height: Space.s6),
        _SectionHeader(title: 'Symptom Heatmap'),
        const SizedBox(height: Space.s2),
        _HeatmapLegend(),
        const SizedBox(height: Space.s2),
        _HeatmapGrid(report: report),
        if (report.worstEpisodes.isNotEmpty) ...[
          const SizedBox(height: Space.s6),
          _SectionHeader(title: 'Worst Episodes'),
          const SizedBox(height: Space.s2),
          _WorstEpisodes(episodes: report.worstEpisodes),
        ],
        if (report.newOrWorsening.isNotEmpty) ...[
          const SizedBox(height: Space.s6),
          _SectionHeader(title: 'New or Worsening'),
          const SizedBox(height: Space.s2),
          _NewOrWorsening(entries: report.newOrWorsening),
        ],
        const SizedBox(height: Space.s6),
        _SectionHeader(title: 'Medication Adherence'),
        const SizedBox(height: Space.s2),
        _MedicationAdherenceCard(adherence: report.medicationAdherence),
        if (report.vitals.isNotEmpty) ...[
          const SizedBox(height: Space.s6),
          _SectionHeader(title: 'Vitals'),
          const SizedBox(height: Space.s2),
          _VitalsCard(vitals: report.vitals),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: BrandColors.concordBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: Space.s2),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.report});
  final OnePagerReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = DateTime.tryParse(report.generatedAt) ?? DateTime.now();
    final endLabel = DateFormat('MMM d').format(now);
    final startLabel = DateFormat(
      'MMM d',
    ).format(now.subtract(Duration(days: report.periodDays)));
    final overall = report.medicationAdherence.overallPct;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.summarize_outlined,
                  color: BrandColors.concordBlue,
                  size: 22,
                ),
                const SizedBox(width: Space.s2),
                Text('$startLabel – $endLabel', style: t.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: Space.s2),
            Text(
              'Generated ${DateFormat('MMM d, y · h:mm a').format(now)}',
              style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
            ),
            if (overall != null) ...[
              const SizedBox(height: Space.s3),
              Row(
                children: [
                  Text('Adherence', style: t.textTheme.bodyMedium),
                  const SizedBox(width: Space.s2),
                  Text(
                    '$overall%',
                    style: numericTextStyle.copyWith(
                      fontSize: 18,
                      color: overall >= 80
                          ? SeverityColors.none
                          : overall >= 50
                          ? SeverityColors.mild
                          : SeverityColors.severe,
                    ),
                  ),
                ],
              ),
            ],
            if (report.newOrWorsening.isNotEmpty) ...[
              const SizedBox(height: Space.s2),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: SeverityColors.moderate,
                  ),
                  const SizedBox(width: Space.s1),
                  Text(
                    '${report.newOrWorsening.length} change${report.newOrWorsening.length == 1 ? '' : 's'} detected',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: SeverityColors.moderate,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Heatmap ───────────────────────────────────────────────────────────

class _HeatmapLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Text('Grade: ', style: t.textTheme.labelSmall),
        const SizedBox(width: Space.s1),
        ...[(0, 'None'), (1, 'Mild'), (2, 'Moderate'), (3, 'Severe')].map(
          (g) => Padding(
            padding: const EdgeInsets.only(right: Space.s2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: SeverityColors.byGrade(g.$1).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: Space.s1),
                Text(
                  g.$2,
                  style: t.textTheme.labelSmall?.copyWith(
                    color: Neutrals.slate,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({required this.report});
  final OnePagerReport report;

  @override
  Widget build(BuildContext context) {
    final dates = report.allDates;
    if (dates.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Text(
            'No symptom data in this period.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    // Group rows by body system
    final bySystem = <String, List<HeatmapRow>>{};
    for (final row in report.heatmapRows) {
      final sys = row.bodySystem.isNotEmpty ? row.bodySystem : 'Other';
      bySystem.putIfAbsent(sys, () => []).add(row);
    }

    final t = Theme.of(context);
    const cellW = 28.0;
    const cellH = 24.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(Space.s3),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header row
              Row(
                children: [
                  const SizedBox(width: 120),
                  ...dates.map((d) {
                    final day = DateFormat('d').format(DateTime.parse(d));
                    final isToday =
                        d == DateFormat('yyyy-MM-dd').format(DateTime.now());
                    return SizedBox(
                      width: cellW,
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: t.textTheme.labelSmall?.copyWith(
                          fontWeight: isToday ? FontWeight.w600 : null,
                          color: isToday
                              ? BrandColors.concordBlue
                              : Neutrals.slate,
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: Space.s1),
              // Body system groups
              ...bySystem.entries.map(
                (sys) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s1),
                      child: Text(
                        sys.key,
                        style: t.textTheme.labelSmall?.copyWith(
                          color: Neutrals.hint,
                        ),
                      ),
                    ),
                    ...sys.value.map(
                      (row) => _HeatmapRow(
                        row: row,
                        dates: dates,
                        cellW: cellW,
                        cellH: cellH,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeatmapRow extends StatelessWidget {
  const _HeatmapRow({
    required this.row,
    required this.dates,
    required this.cellW,
    required this.cellH,
  });
  final HeatmapRow row;
  final List<String> dates;
  final double cellW;
  final double cellH;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 120,
          height: cellH + 4,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              row.termName,
              style: t.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        ...dates.map((d) {
          final grade = row.gradesByDate[d] ?? -1;
          final hasData = grade >= 0;
          return Container(
            width: cellW,
            height: cellH + 4,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: hasData
                  ? SeverityColors.byGrade(
                      grade,
                    ).withValues(alpha: 0.25 + grade * 0.15)
                  : null,
              borderRadius: BorderRadius.circular(3),
            ),
            child: hasData
                ? Center(
                    child: Text(
                      '$grade',
                      style: numericTextStyle.copyWith(
                        fontSize: 11,
                        color: SeverityColors.byGrade(grade),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : null,
          );
        }),
      ],
    );
  }
}

// ── Worst Episodes ────────────────────────────────────────────────────

class _WorstEpisodes extends StatelessWidget {
  const _WorstEpisodes({required this.episodes});
  final List<WorstEpisode> episodes;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final maxGrade = episodes.fold<double>(
      0,
      (m, e) => e.grade > m ? e.grade : m,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          children: episodes.map((e) {
            final barPct = maxGrade > 0 ? e.grade / maxGrade : 0.0;
            final color = SeverityColors.byGrade(e.grade.round());
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          e.termName,
                          style: t.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${e.grade.toStringAsFixed(1)} avg',
                        style: numericTextStyle.copyWith(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s1),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: barPct.clamp(0.0, 1.0),
                      backgroundColor: Neutrals.mist,
                      color: color,
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── New or Worsening ──────────────────────────────────────────────────

class _NewOrWorsening extends StatelessWidget {
  const _NewOrWorsening({required this.entries});
  final List<NewOrWorseningEntry> entries;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Column(
        children: entries.map((e) {
          final isNew = e.direction == 'new';
          final icon = isNew ? Icons.add_circle_outline : Icons.trending_up;
          final label = isNew ? 'New' : 'Worsened';
          return ListTile(
            leading: Icon(
              icon,
              color: isNew ? SeverityColors.mild : SeverityColors.moderate,
              size: 22,
            ),
            title: Text(e.termName, style: t.textTheme.bodyMedium),
            subtitle: Text(
              isNew
                  ? 'Grade ${e.currentAvgGrade.toStringAsFixed(1)}'
                  : '${e.priorAvgGrade.toStringAsFixed(1)} → ${e.currentAvgGrade.toStringAsFixed(1)}',
              style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s2,
                vertical: Space.s1,
              ),
              decoration: BoxDecoration(
                color: (isNew ? SeverityColors.mild : SeverityColors.moderate)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                label,
                style: t.textTheme.labelSmall?.copyWith(
                  color: isNew ? SeverityColors.mild : SeverityColors.moderate,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Medication Adherence ──────────────────────────────────────────────

class _MedicationAdherenceCard extends StatelessWidget {
  const _MedicationAdherenceCard({required this.adherence});
  final MedicationAdherence adherence;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final meds = adherence.byMedication;

    if (meds.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Text(
            'No medication data in this period.',
            style: t.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          children: meds.map((m) {
            final color = m.adherencePct >= 80
                ? SeverityColors.none
                : m.adherencePct >= 50
                ? SeverityColors.mild
                : SeverityColors.severe;
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          m.displayName,
                          style: t.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${m.adherencePct}%',
                        style: numericTextStyle.copyWith(
                          fontSize: 13,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s1),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: m.adherencePct / 100,
                      backgroundColor: Neutrals.mist,
                      color: color,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    '${m.taken}/${m.total} taken · ${m.skipped} skipped · ${m.missed} missed',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.slate,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Vitals ────────────────────────────────────────────────────────────

class _VitalsCard extends StatelessWidget {
  const _VitalsCard({required this.vitals});
  final List<VitalsEntry> vitals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    final stepsAvg = _avg<int>(vitals.map((v) => v.steps).toList());
    final hrAvg = _avg<int>(vitals.map((v) => v.avgHrBpm).toList());
    final sleepAvg = _avg<double>(vitals.map((v) => v.sleepHours).toList());
    final weightAvg = _avg<double>(vitals.map((v) => v.weightKg).toList());
    final bpSysAvg = _avg<int>(vitals.map((v) => v.bpSysAvg).toList());
    final bpDiaAvg = _avg<int>(vitals.map((v) => v.bpDiaAvg).toList());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          children: [
            _VitalRow(
              icon: Icons.directions_walk,
              label: 'Steps',
              value: stepsAvg != null ? '${stepsAvg.round()}' : null,
              subtitle: 'avg/day',
            ),
            const Divider(height: Space.s4),
            _VitalRow(
              icon: Icons.favorite_outline,
              label: 'Heart Rate',
              value: hrAvg != null ? '${hrAvg.round()}' : null,
              subtitle: 'bpm avg',
            ),
            const Divider(height: Space.s4),
            _VitalRow(
              icon: Icons.bedtime_outlined,
              label: 'Sleep',
              value: sleepAvg != null ? '${sleepAvg.toStringAsFixed(1)}' : null,
              subtitle: 'hours avg',
            ),
            const Divider(height: Space.s4),
            _VitalRow(
              icon: Icons.monitor_weight_outlined,
              label: 'Weight',
              value: weightAvg != null
                  ? '${weightAvg.toStringAsFixed(1)}'
                  : null,
              subtitle: 'kg avg',
            ),
            if (bpSysAvg != null || bpDiaAvg != null) ...[
              const Divider(height: Space.s4),
              _VitalRow(
                icon: Icons.speed,
                label: 'Blood Pressure',
                value: bpSysAvg != null && bpDiaAvg != null
                    ? '${bpSysAvg.round()}/${bpDiaAvg.round()}'
                    : null,
                subtitle: 'sys/dia avg',
              ),
            ],
          ],
        ),
      ),
    );
  }

  T? _avg<T extends num>(List<T?> values) {
    final nonNull = values.whereType<T>().toList();
    if (nonNull.isEmpty) return null;
    final sum = nonNull.fold<num>(0, (a, b) => a + b);
    return (sum / nonNull.length) as T;
  }
}

class _VitalRow extends StatelessWidget {
  const _VitalRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });
  final IconData icon;
  final String label;
  final String? value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: BrandColors.concordBlue, size: 20),
        const SizedBox(width: Space.s3),
        Expanded(child: Text(label, style: t.textTheme.bodyMedium)),
        if (value != null)
          Text(
            value!,
            style: numericTextStyle.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (value != null) ...[
          const SizedBox(width: Space.s1),
          Text(
            subtitle,
            style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
          ),
        ],
      ],
    );
  }
}
