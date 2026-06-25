import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';

final _gradeColors = [
  Colors.transparent,
  const Color(0xFFD4EDDA),
  const Color(0xFFFFEAA7),
  const Color(0xFFF8D7DA),
];

final _gradeTextColors = [
  Colors.transparent,
  const Color(0xFF155724),
  const Color(0xFF856404),
  const Color(0xFF721C24),
];

final _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

final _symptomHistoryProvider = FutureProvider.autoDispose
    .family<List<SymptomDay>, String>((ref, patientId) async {
      final supabase = ref.watch(supabaseClientProvider);
      final session = supabase.auth.currentSession;
      if (session == null) return [];

      final apiBase = ref.read(apiBaseUrlProvider);
      final res = await http
          .get(
            Uri.parse('$apiBase/api/symptoms/history?days=90'),
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return [];

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final terms = body['terms'] as List<dynamic>? ?? [];

      // Flatten entries into SymptomDay list.
      final dayMap = <String, SymptomDay>{};
      for (final t in terms) {
        final tMap = t as Map<String, dynamic>;
        final code = tMap['pro_ctcae_code'] as String? ?? '';
        final name = tMap['name'] as String? ?? code;
        final entries = tMap['entries'] as List<dynamic>? ?? [];
        for (final e in entries) {
          final eMap = e as Map<String, dynamic>;
          final date = eMap['date'] as String? ?? '';
          final grade = eMap['grade'] as int? ?? 0;
          dayMap.putIfAbsent(
            date,
            () => SymptomDay(date: date, maxGrade: 0, symptoms: []),
          );
          dayMap[date]!.symptoms.add(
            SymptomEntry(termCode: code, termName: name, grade: grade),
          );
          dayMap[date]!.maxGrade = max(dayMap[date]!.maxGrade, grade);
        }
      }

      return dayMap.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    });

class SymptomDay {
  final String date;
  int maxGrade;
  List<SymptomEntry> symptoms;

  SymptomDay({
    required this.date,
    required this.maxGrade,
    required this.symptoms,
  });
}

class SymptomEntry {
  final String termCode;
  final String termName;
  final int grade;

  SymptomEntry({
    required this.termCode,
    required this.termName,
    required this.grade,
  });
}

class SymptomHistoryScreen extends ConsumerWidget {
  const SymptomHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = ref.watch(supabaseClientProvider);
    final user = supabase.auth.currentUser;
    final patientId = user?.id ?? '';

    final historyAsync = ref.watch(_symptomHistoryProvider(patientId));

    return Scaffold(
      appBar: AppBar(title: const Text('Symptom history')),
      body: SafeArea(
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (days) => RefreshIndicator(
            onRefresh: () =>
                ref.refresh(_symptomHistoryProvider(patientId).future),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Space.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last 90 days',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: Neutrals.hint),
                  ),
                  const SizedBox(height: Space.s3),
                  _CalendarHeatmap(days: days),
                  const SizedBox(height: Space.s5),
                  Text(
                    'Symptom breakdown',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  ..._buildSymptomSparklines(days, context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSymptomSparklines(
    List<SymptomDay> days,
    BuildContext context,
  ) {
    final allTerms = <String, String>{};
    final termGrades = <String, List<int>>{};

    for (final day in days) {
      for (final s in day.symptoms) {
        allTerms[s.termCode] = s.termName;
        termGrades.putIfAbsent(s.termCode, () => []);
      }
    }

    final sortedDays = days.reversed.toList();
    for (final day in sortedDays) {
      for (final s in day.symptoms) {
        termGrades[s.termCode]!.add(s.grade);
      }
    }

    return allTerms.entries.map((entry) {
      final grades = termGrades[entry.key] ?? [];
      final sparklineHeight = 40.0;
      final barWidth = max(3.0, (sparklineHeight - 20) / 3);

      return Padding(
        padding: const EdgeInsets.only(bottom: Space.s3),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Space.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Space.s2),
                SizedBox(
                  height: sparklineHeight,
                  child: CustomPaint(
                    size: Size(double.infinity, sparklineHeight),
                    painter: _SparklinePainter(
                      grades: grades,
                      barWidth: barWidth,
                      barSpacing: 2,
                    ),
                  ),
                ),
                if (grades.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        _GradeDot(0),
                        const SizedBox(width: 2),
                        Text(
                          'None',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: Space.s2),
                        _GradeDot(1),
                        const SizedBox(width: 2),
                        Text(
                          'Mild',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: Space.s2),
                        _GradeDot(2),
                        const SizedBox(width: 2),
                        Text(
                          'Mod',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: Space.s2),
                        _GradeDot(3),
                        const SizedBox(width: 2),
                        Text(
                          'Sev',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
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
    }).toList();
  }
}

class _GradeDot extends StatelessWidget {
  final int grade;
  const _GradeDot(this.grade);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _gradeColors[grade],
        shape: BoxShape.circle,
        border: Border.all(
          color: _gradeTextColors[grade].withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> grades;
  final double barWidth;
  final double barSpacing;

  _SparklinePainter({
    required this.grades,
    required this.barWidth,
    required this.barSpacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (grades.isEmpty) return;

    final paint = Paint();
    final xStart = 0.0;

    for (int i = 0; i < grades.length; i++) {
      final grade = grades[i];
      final barH = ((grade + 1) / 4) * size.height;
      final x = xStart + i * (barWidth + barSpacing);

      paint.color = _gradeColors[grade];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - barH, barWidth, barH),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) => true;
}

class _CalendarHeatmap extends StatelessWidget {
  final List<SymptomDay> days;

  const _CalendarHeatmap({required this.days});

  @override
  Widget build(BuildContext context) {
    final dayMap = <String, int>{};
    for (final d in days) {
      dayMap[d.date] = d.maxGrade;
    }

    if (days.isEmpty) return const SizedBox.shrink();

    final sorted = days.map((d) => d.date).toList()..sort();
    final firstDate = DateTime.parse(sorted.first);
    final lastDate = DateTime.parse(sorted.last);
    final months = _monthsBetween(firstDate, lastDate);

    return Column(
      children: [
        ...months.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: Space.s4),
            child: _MonthCard(year: m.year, month: m.month, dayMap: dayMap),
          ),
        ),
        _buildLegend(),
      ],
    );
  }

  /// Generate first-of-month DateTimes for each month in [start, end].
  List<DateTime> _monthsBetween(DateTime start, DateTime end) {
    final result = <DateTime>[];
    var cursor = DateTime(start.year, start.month, 1);
    final stop = DateTime(end.year, end.month, 1);
    while (!cursor.isAfter(stop)) {
      result.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return result;
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Text(
          'Worst grade: ',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        ...[0, 1, 2, 3].map(
          (g) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _gradeColors[g],
                    borderRadius: BorderRadius.circular(2),
                    border: g > 0
                        ? Border.all(
                            color: _gradeTextColors[g].withValues(alpha: 0.3),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  ['\u2014', 'Mild', 'Mod', 'Sev'][g],
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  final int year;
  final int month;
  final Map<String, int> dayMap;

  const _MonthCard({
    required this.year,
    required this.month,
    required this.dayMap,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;
    final totalCells = startWeekday + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_monthNames[month - 1]} $year',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Space.s3),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: 'SMTWTFS'
                      .split('')
                      .map(
                        (d) => SizedBox(
                          width: 28,
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 4),
                for (int row = 0; row < rows; row++) ...[
                  if (row > 0) const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(7, (col) {
                      final cellIndex = row * 7 + col;
                      final dayNum = cellIndex - startWeekday + 1;

                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return const SizedBox(width: 28, height: 28);
                      }

                      final dateStr =
                          '$year-${month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';
                      final grade = dayMap[dateStr] ?? 0;

                      return Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _gradeColors[grade],
                          borderRadius: BorderRadius.circular(4),
                          border: grade > 0
                              ? Border.all(
                                  color: _gradeTextColors[grade].withValues(
                                    alpha: 0.3,
                                  ),
                                )
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 11,
                              color: grade > 0
                                  ? _gradeTextColors[grade]
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }),
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
