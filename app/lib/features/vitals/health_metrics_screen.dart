import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/health_repository.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Health metrics history (HK-04). Shows trend charts and recent values
/// for all logged metric types (steps, weight, HR, BP, glucose, etc.).
class HealthMetricsScreen extends ConsumerStatefulWidget {
  const HealthMetricsScreen({super.key});

  @override
  ConsumerState<HealthMetricsScreen> createState() =>
      _HealthMetricsScreenState();
}

class _HealthMetricsScreenState extends ConsumerState<HealthMetricsScreen> {
  String? _selectedType;
  List<MetricTypeGroup> _types = [];
  bool _initialLoad = true;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final metricsAsync = ref.watch(healthMetricsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Health metrics')),
      body: SafeArea(
        child: metricsAsync.when(
          loading: () => _initialLoad
              ? const Center(child: CircularProgressIndicator())
              : const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.s6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: SeverityColors.severe,
                  ),
                  const SizedBox(height: Space.s3),
                  Text(
                    '$e',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: SeverityColors.severe,
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  FilledButton(
                    onPressed: () => ref.invalidate(healthMetricsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (types) {
            _initialLoad = false;
            if (_selectedType == null && types.isNotEmpty) {
              _selectedType = types.first.type;
            }
            if (types.isEmpty) return _EmptyState(t: t);
            return Column(
              children: [
                _TypeChips(
                  types: types,
                  selected: _selectedType,
                  onSelected: (t) => setState(() => _selectedType = t),
                ),
                Expanded(
                  child: _selected != null
                      ? _MetricDetail(
                          group: types.firstWhere(
                            (g) => g.type == _selectedType,
                          ),
                          onRefresh: () =>
                              ref.invalidate(healthMetricsProvider),
                        )
                      : const SizedBox(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.t});
  final ThemeData t;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monitor_heart_outlined, size: 56, color: Neutrals.hint),
            const SizedBox(height: Space.s4),
            Text('No health metrics yet', style: t.textTheme.titleLarge),
            const SizedBox(height: Space.s2),
            Text(
              'Log vitals manually or connect Apple Health / Health Connect '
              'to see your trends here.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
            ),
            const SizedBox(height: Space.s4),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Log vitals'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChips extends StatelessWidget {
  const _TypeChips({
    required this.types,
    required this.selected,
    required this.onSelected,
  });
  final List<MetricTypeGroup> types;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s2,
        Space.s5,
        Space.s1,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Neutrals.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: types.map((t) {
            final isSelected = t.type == selected;
            return Padding(
              padding: const EdgeInsets.only(right: Space.s2),
              child: FilterChip(
                label: Text(t.label),
                selected: isSelected,
                onSelected: (_) => onSelected(t.type),
                avatar: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(int.parse(t.color.replaceFirst('#', '0xFF'))),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _MetricDetail extends StatelessWidget {
  const _MetricDetail({required this.group, required this.onRefresh});
  final MetricTypeGroup group;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final chartColor = Color(int.parse(group.color.replaceFirst('#', '0xFF')));
    final samples = group.samples;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s3,
          Space.s5,
          Space.s10,
        ),
        children: [
          // Summary card.
          Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: chartColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: chartColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(
                      label: 'Latest',
                      value: group.latest,
                      unit: group.unit,
                      color: chartColor,
                      metricType: group.type,
                    ),
                    _Stat(
                      label: 'Avg',
                      value: group.avg,
                      unit: group.unit,
                      color: chartColor,
                      metricType: group.type,
                    ),
                    _Stat(
                      label: 'Min',
                      value: group.min,
                      unit: group.unit,
                      color: chartColor,
                      metricType: group.type,
                    ),
                    _Stat(
                      label: 'Max',
                      value: group.max,
                      unit: group.unit,
                      color: chartColor,
                      metricType: group.type,
                    ),
                  ],
                ),
                const SizedBox(height: Space.s3),
                Text(
                  '${group.count} readings in last 90 days',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: Neutrals.slate,
                  ),
                ),
              ],
            ),
          ),

          // Chart.
          if (samples.length >= 2) ...[
            const SizedBox(height: Space.s5),
            Text('Trend', style: t.textTheme.titleSmall),
            const SizedBox(height: Space.s2),
            SizedBox(
              height: 200,
              child: _LineChart(samples: samples, color: chartColor),
            ),
          ],

          // Recent values list.
          const SizedBox(height: Space.s5),
          Text('Recent readings', style: t.textTheme.titleSmall),
          const SizedBox(height: Space.s2),
          ...samples
              .take(20)
              .map(
                (s) => _SampleRow(
                  sample: s,
                  color: chartColor,
                  metricType: group.type,
                ),
              ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    this.value,
    required this.unit,
    required this.color,
    this.metricType,
  });
  final String label;
  final num? value;
  final String unit;
  final Color color;
  final String? metricType;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final range = value != null && metricType != null
        ? referenceRangeFor(metricType!, value!)
        : null;
    final isAbnormal =
        range != null &&
        range.label != 'Normal' &&
        range.label != '' &&
        range.label != 'Individual' &&
        range.label != 'Goal dependent';
    final flagColor = isAbnormal ? SeverityColors.warn : null;
    return Column(
      children: [
        Text(
          label,
          style: t.textTheme.labelSmall?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s1),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAbnormal)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.flag, size: 14, color: flagColor),
              ),
            Text(
              value != null ? _format(value!) : '--',
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isAbnormal ? flagColor : color,
              ),
            ),
          ],
        ),
        Text(
          unit,
          style: t.textTheme.labelSmall?.copyWith(color: Neutrals.hint),
        ),
        if (range != null && range.low != null)
          Text(
            '${range.low}-${range.high}',
            style: t.textTheme.labelSmall?.copyWith(
              color: Neutrals.hint,
              fontSize: 10,
            ),
          ),
      ],
    );
  }

  String _format(num v) {
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({
    required this.sample,
    required this.color,
    this.metricType,
  });
  final MetricSample sample;
  final Color color;
  final String? metricType;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final date = DateFormat.MMMd().add_jm().format(
      DateTime.parse(sample.measuredAt),
    );
    final val =
        sample.value is double && sample.value == sample.value.roundToDouble()
        ? sample.value.toInt().toString()
        : sample.value.toStringAsFixed(1);
    final range = metricType != null
        ? referenceRangeFor(metricType!, sample.value)
        : null;
    final isAbnormal =
        range != null &&
        range.label != 'Normal' &&
        range.label != '' &&
        range.label != 'Individual' &&
        range.label != 'Goal dependent';
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s1),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAbnormal
                  ? SeverityColors.warn
                  : color.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: Space.s2),
          if (isAbnormal)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.flag, size: 14, color: SeverityColors.warn),
            ),
          Text(
            '$val ${sample.unit}',
            style: t.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: isAbnormal ? SeverityColors.warn : null,
            ),
          ),
          const Spacer(),
          Text(
            date,
            style: t.textTheme.labelSmall?.copyWith(color: Neutrals.slate),
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.samples, required this.color});
  final List<MetricSample> samples;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(samples: samples, color: color),
      size: const Size(double.infinity, 200),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.samples, required this.color});
  final List<MetricSample> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final values = samples.map((s) => s.value).toList();
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final range = (max - min).abs() > 0 ? max - min : 1.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();
    final padding = 16.0;
    final chartW = size.width - padding * 2;
    final chartH = size.height - padding * 2;

    for (var i = 0; i < values.length; i++) {
      final x = padding + (i / (values.length - 1)) * chartW;
      final y = padding + chartH - ((values[i] - min) / range) * chartH;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, padding + chartH);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Close fill path.
    final lastX = padding + chartW;
    final lastY = padding + chartH;
    fillPath.lineTo(lastX, lastY);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw dots on data points.
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var i = 0; i < values.length; i++) {
      final x = padding + (i / (values.length - 1)) * chartW;
      final y = padding + chartH - ((values[i] - min) / range) * chartH;
      canvas.drawCircle(
        Offset(x, y),
        i == values.length - 1 ? 4 : 2.5,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.samples != samples || old.color != color;
}
