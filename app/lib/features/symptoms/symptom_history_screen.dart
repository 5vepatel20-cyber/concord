import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';

final _symptomHistoryProvider = FutureProvider.autoDispose
    .family<List<SymptomDay>, String>((ref, patientId) async {
  final supabase = ref.watch(supabaseClientProvider);

  const thirtyDaysAgo = Duration(days: 30);
  final since = DateTime.now().subtract(thirtyDaysAgo).toIso8601String();

  final { data: reports } = await supabase
      .from('symptom_report')
      .select('''
        id,
        reported_at,
        symptom_response!inner(
          composite_grade,
          symptom_term!inner(pro_ctcae_code, display_name)
        )
      ''')
      .gte('reported_at', since)
      .order('reported_at', ascending: false);

  if (reports == null) return [];

  final dayMap = <String, SymptomDay>{};
  for (final r in reports as List<dynamic>) {
    final enc = r as Map<String, dynamic>;
    final date = DateTime.parse(enc['reported_at'] as String);
    final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final responses = enc['symptom_response'] as List<dynamic>;

    dayMap.putIfAbsent(dateKey, () => SymptomDay(date: dateKey, maxGrade: 0, symptoms: []));

    for (final sr in responses) {
      final s = sr as Map<String, dynamic>;
      final term = s['symptom_term'] as Map<String, dynamic>;
      final grade = (s['composite_grade'] as num).toInt();
      final symptom = SymptomEntry(
        termCode: term['pro_ctcae_code'] as String,
        termName: term['display_name'] as String,
        grade: grade,
      );
      dayMap[dateKey]!.symptoms.add(symptom);
      dayMap[dateKey]!.maxGrade = max(dayMap[dateKey]!.maxGrade, grade);
    }
  }

  return dayMap.values.toList()..sort((a, b) => b.date.compareTo(a.date));
});

class SymptomDay {
  final String date;
  int maxGrade;
  List<SymptomEntry> symptoms;

  SymptomDay({required this.date, required this.maxGrade, required this.symptoms});
}

class SymptomEntry {
  final String termCode;
  final String termName;
  final int grade;

  SymptomEntry({required this.termCode, required this.termName, required this.grade});
}

final _gradeColors = [
  Colors.transparent,           // 0: none
  Color(0xFFD4EDDA),            // 1: mild
  Color(0xFFFFEAA7),            // 2: moderate
  Color(0xFFF8D7DA),            // 3: severe
];

final _gradeTextColors = [
  Colors.transparent,
  Color(0xFF155724),
  Color(0xFF856404),
  Color(0xFF721C24),
];

class SymptomHistoryScreen extends ConsumerWidget {
  const SymptomHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = ref.watch(supabaseClientProvider);
    final user = supabase.auth.currentUser;
    final patientId = user?.id ?? '';

    final historyAsync = ref.watch(_symptomHistoryProvider(patientId));

    return Scaffold(
      appBar: AppBar(title: const Text('Symptom History')),
      body: SafeArea(
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (days) => SingleChildScrollView(
            padding: const EdgeInsets.all(Space.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CalendarHeatmap(days: days),
                const SizedBox(height: Space.s5),
                Text('Symptom Breakdown', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: Space.s3),
                ..._buildSymptomSparklines(days, context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSymptomSparklines(List<SymptomDay> days, BuildContext context) {
    final allTerms = <String, String>{};
    final termGrades = <String, List<int>>{};

    for (final day in days) {
      for (final s in day.symptoms) {
        allTerms[s.termCode] = s.termName;
        termGrades.putIfAbsent(s.termCode, () => []);
      }
    }

    // Reverse days for chronological order
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
                Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                        Text('None', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        const SizedBox(width: Space.s2),
                        _GradeDot(1),
                        const SizedBox(width: 2),
                        Text('Mild', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        const SizedBox(width: Space.s2),
                        _GradeDot(2),
                        const SizedBox(width: 2),
                        Text('Mod', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        const SizedBox(width: Space.s2),
                        _GradeDot(3),
                        const SizedBox(width: 2),
                        Text('Sev', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
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
        border: Border.all(color: _gradeTextColors[grade].withValues(alpha: 0.5)),
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
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // Sunday = 0

    final dayMap = <String, int>{};
    for (final d in days) {
      dayMap[d.date] = d.maxGrade;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_monthNames[now.month - 1]} ${now.year}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Space.s3),
            _buildGrid(dayMap, firstDay, lastDay, startWeekday),
            const SizedBox(height: Space.s2),
            _buildLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(Map<String, int> dayMap, DateTime firstDay, DateTime lastDay, int startWeekday) {
    final daysInMonth = lastDay.day;
    final totalCells = startWeekday + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: 'SMTWTFS'.split('').map((d) => SizedBox(
            width: 28,
            child: Text(d, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          )).toList(),
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

              final dateStr = '${firstDay.year}-${firstDay.month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';
              final grade = dayMap[dateStr] ?? 0;

              return Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _gradeColors[grade],
                  borderRadius: BorderRadius.circular(4),
                  border: grade > 0 ? Border.all(color: _gradeTextColors[grade].withValues(alpha: 0.3)) : null,
                ),
                child: Center(
                  child: Text(
                    '$dayNum',
                    style: TextStyle(
                      fontSize: 11,
                      color: grade > 0 ? _gradeTextColors[grade] : Colors.grey.shade700,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Text('Worst grade: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ...[0, 1, 2, 3].map((g) => Padding(
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
                  border: g > 0 ? Border.all(color: _gradeTextColors[g].withValues(alpha: 0.3)) : null,
                ),
              ),
              const SizedBox(width: 2),
              Text(['—', 'Mild', 'Mod', 'Sev'][g], style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
            ],
          ),
        )),
      ],
    );
  }
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
