// Report repository — read-only views of `symptom_report` + `symptom_response`.
// Phase 1.0 always reads from Supabase (no offline cache for reports).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository(ref);
});

class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.reportedAt,
    required this.recallWindow,
    required this.source,
    required this.topGrade,
  });

  final String id;
  final DateTime reportedAt;
  final String recallWindow; // 'now' | 'past_7_days'
  final String source; // 'self' | 'caregiver' | 'voice'
  final int topGrade; // 0..3 — max composite_grade across responses
}

class ReportDetail {
  const ReportDetail({
    required this.summary,
    required this.responses,
    required this.freeText,
  });

  final ReportSummary summary;
  final List<ResponseDetail> responses;
  final String? freeText;
}

class ResponseDetail {
  const ResponseDetail({
    required this.termId,
    required this.termLabel,
    required this.compositeGrade,
  });

  final String termId;
  final String termLabel;
  final int compositeGrade;
}

class ReportRepository {
  ReportRepository(this._ref);
  final Ref _ref;

  Future<List<ReportSummary>> listRecent({int limit = 50}) async {
    final supabase = _ref.read(supabaseClientProvider);
    final user = supabase.auth.currentUser;
    if (user == null) return const [];

    final reports = await supabase
        .from('symptom_report')
        .select('id, reported_at, recall_window, source')
        .eq('patient_id', user.id)
        .order('reported_at', ascending: false)
        .limit(limit);

    final ids = (reports as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['id'] as String)
        .toList();
    if (ids.isEmpty) return const [];

    // Top composite grade per report (max across responses).
    final responses = await supabase
        .from('symptom_response')
        .select('report_id, composite_grade')
        .inFilter('report_id', ids);

    final topByReport = <String, int>{};
    for (final r in (responses as List).cast<Map<String, dynamic>>()) {
      final rid = r['report_id'] as String;
      final g = (r['composite_grade'] as num?)?.toInt() ?? 0;
      final cur = topByReport[rid] ?? 0;
      if (g > cur) topByReport[rid] = g;
    }

    return reports.cast<Map<String, dynamic>>().map((r) {
      final id = r['id'] as String;
      return ReportSummary(
        id: id,
        reportedAt: DateTime.parse(r['reported_at'] as String).toLocal(),
        recallWindow: r['recall_window'] as String? ?? 'now',
        source: r['source'] as String? ?? 'self',
        topGrade: topByReport[id] ?? 0,
      );
    }).toList(growable: false);
  }

  Future<ReportDetail?> fetchDetail(String reportId) async {
    final supabase = _ref.read(supabaseClientProvider);
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final reportRows = await supabase
        .from('symptom_report')
        .select('id, reported_at, recall_window, source, free_text')
        .eq('id', reportId)
        .eq('patient_id', user.id)
        .limit(1);
    final rows = (reportRows as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    final head = rows.first;

    final responses = await supabase
        .from('symptom_response')
        .select('term_id, composite_grade')
        .eq('report_id', reportId);

    // Hydrate term labels in one query.
    final termIds = (responses as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['term_id'] as String)
        .toSet()
        .toList();
    final terms = termIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await supabase
                .from('symptom_term')
                .select('id, display_name')
                .inFilter('id', termIds) as List)
            .cast<Map<String, dynamic>>();
    final labelById = {
      for (final t in terms) t['id'] as String: t['display_name'] as String,
    };

    final responseDetails = responses.map((r) {
      final tid = r['term_id'] as String;
      return ResponseDetail(
        termId: tid,
        termLabel: labelById[tid] ?? '(unknown term)',
        compositeGrade: (r['composite_grade'] as num?)?.toInt() ?? 0,
      );
    }).toList()
      ..sort((a, b) => b.compositeGrade.compareTo(a.compositeGrade));

    final topGrade = responseDetails.isEmpty
        ? 0
        : responseDetails.first.compositeGrade;

    return ReportDetail(
      summary: ReportSummary(
        id: head['id'] as String,
        reportedAt: DateTime.parse(head['reported_at'] as String).toLocal(),
        recallWindow: head['recall_window'] as String? ?? 'now',
        source: head['source'] as String? ?? 'self',
        topGrade: topGrade,
      ),
      responses: responseDetails,
      freeText: head['free_text'] as String?,
    );
  }
}

/// Group summaries into week buckets, oldest first.
Map<DateTime, List<ReportSummary>> groupByWeek(
  List<ReportSummary> reports,
) {
  final out = <DateTime, List<ReportSummary>>{};
  for (final r in reports) {
    final weekStart = _weekStartOf(r.reportedAt);
    out.putIfAbsent(weekStart, () => []).add(r);
  }
  return out;
}

DateTime _weekStartOf(DateTime d) {
  // Monday-start week.
  final monday = d.subtract(Duration(days: d.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
}

String weekLabel(DateTime weekStart) {
  final fmt = DateFormat('MMM d');
  return 'Week of ${fmt.format(weekStart)}';
}