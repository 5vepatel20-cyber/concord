// Report repository — read-only views of `symptom_report` + `symptom_response`.
// Phase 1.0 always reads from Supabase (no offline cache for reports).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

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

// ── One-pager models (RPT-03) ────────────────────────────────────────

class OnePagerReport {
  final String reportId;
  final String generatedAt;
  final int periodDays;
  final List<HeatmapRow> heatmapRows;
  final List<WorstEpisode> worstEpisodes;
  final List<NewOrWorseningEntry> newOrWorsening;
  final MedicationAdherence medicationAdherence;
  final List<VitalsEntry> vitals;
  final String? narrative;

  OnePagerReport({
    required this.reportId,
    required this.generatedAt,
    required this.periodDays,
    required this.heatmapRows,
    required this.worstEpisodes,
    required this.newOrWorsening,
    required this.medicationAdherence,
    required this.vitals,
    this.narrative,
  });

  factory OnePagerReport.fromJson(Map<String, dynamic> json) {
    final rawHeatmap =
        (json['symptom_heatmap'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final dateSet = <String>{};
    final termMap = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawHeatmap) {
      final date = entry['date'] as String;
      final code = entry['term_code'] as String;
      dateSet.add(date);
      termMap.putIfAbsent(code, () => []).add(entry);
    }
    final sortedDates = dateSet.toList()..sort();

    final heatmapRows = termMap.entries.map((e) {
      final first = e.value.first;
      final gradesByDate = <String, int>{};
      for (final entry in e.value) {
        final date = entry['date'] as String;
        gradesByDate[date] = (entry['grade'] as num).toInt();
      }
      return HeatmapRow(
        termCode: e.key,
        termName: first['term_name'] as String? ?? e.key,
        bodySystem: first['body_system'] as String? ?? '',
        gradesByDate: gradesByDate,
      );
    }).toList()..sort((a, b) => a.bodySystem.compareTo(b.bodySystem));

    final rawWorst =
        (json['worst_episodes'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final worstEpisodes = rawWorst
        .map(
          (w) => WorstEpisode(
            termCode: w['term_code'] as String,
            termName: w['term_name'] as String,
            grade: (w['grade'] as num).toDouble(),
            count: (w['count'] as num).toInt(),
          ),
        )
        .toList();

    final rawNew =
        (json['new_or_worsening'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final newOrWorsening = rawNew
        .map(
          (n) => NewOrWorseningEntry(
            termCode: n['term_code'] as String,
            termName: n['term_name'] as String,
            priorAvgGrade: (n['prior_avg_grade'] as num).toDouble(),
            currentAvgGrade: (n['current_avg_grade'] as num).toDouble(),
            direction: n['direction'] as String,
          ),
        )
        .toList();

    final adherenceJson =
        json['medication_adherence'] as Map<String, dynamic>? ?? {};
    final rawByMed =
        (adherenceJson['by_medication'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final byMedication = rawByMed
        .map(
          (m) => MedAdherence(
            medicationId: m['medication_id'] as String,
            displayName: m['display_name'] as String,
            total: (m['total'] as num).toInt(),
            taken: (m['taken'] as num).toInt(),
            skipped: (m['skipped'] as num).toInt(),
            missed: (m['missed'] as num).toInt(),
            takenLate: (m['taken_late'] as num).toInt(),
            adherencePct: (m['adherence_pct'] as num).toInt(),
          ),
        )
        .toList();

    final rawVitals =
        (json['vitals'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final vitals = rawVitals
        .map(
          (v) => VitalsEntry(
            date: v['date'] as String,
            steps: v['steps'] as int?,
            avgHrBpm: v['avg_hr_bpm'] as int?,
            sleepHours: (v['sleep_hours'] as num?)?.toDouble(),
            weightKg: (v['weight_kg'] as num?)?.toDouble(),
            bpSysAvg: v['bp_sys_avg'] as int?,
            bpDiaAvg: v['bp_dia_avg'] as int?,
          ),
        )
        .toList();

    return OnePagerReport(
      reportId: json['report_id'] as String,
      generatedAt: json['generated_at'] as String? ?? '',
      periodDays: (json['period_days'] as num?)?.toInt() ?? 14,
      heatmapRows: heatmapRows,
      worstEpisodes: worstEpisodes,
      newOrWorsening: newOrWorsening,
      medicationAdherence: MedicationAdherence(
        byMedication: byMedication,
        overallPct: (adherenceJson['overall_pct'] as num?)?.toInt(),
      ),
      vitals: vitals,
      narrative: json['narrative'] as String?,
    );
  }

  List<String> get allDates {
    final set = <String>{};
    for (final row in heatmapRows) {
      set.addAll(row.gradesByDate.keys);
    }
    return set.toList()..sort();
  }
}

class HeatmapRow {
  final String termCode;
  final String termName;
  final String bodySystem;
  final Map<String, int> gradesByDate;

  HeatmapRow({
    required this.termCode,
    required this.termName,
    required this.bodySystem,
    required this.gradesByDate,
  });
}

class WorstEpisode {
  final String termCode;
  final String termName;
  final double grade;
  final int count;

  WorstEpisode({
    required this.termCode,
    required this.termName,
    required this.grade,
    required this.count,
  });
}

class NewOrWorseningEntry {
  final String termCode;
  final String termName;
  final double priorAvgGrade;
  final double currentAvgGrade;
  final String direction;

  NewOrWorseningEntry({
    required this.termCode,
    required this.termName,
    required this.priorAvgGrade,
    required this.currentAvgGrade,
    required this.direction,
  });
}

class MedicationAdherence {
  final List<MedAdherence> byMedication;
  final int? overallPct;

  MedicationAdherence({required this.byMedication, this.overallPct});
}

class MedAdherence {
  final String medicationId;
  final String displayName;
  final int total;
  final int taken;
  final int skipped;
  final int missed;
  final int takenLate;
  final int adherencePct;

  MedAdherence({
    required this.medicationId,
    required this.displayName,
    required this.total,
    required this.taken,
    required this.skipped,
    required this.missed,
    required this.takenLate,
    required this.adherencePct,
  });
}

class VitalsEntry {
  final String date;
  final int? steps;
  final int? avgHrBpm;
  final double? sleepHours;
  final double? weightKg;
  final int? bpSysAvg;
  final int? bpDiaAvg;

  VitalsEntry({
    required this.date,
    this.steps,
    this.avgHrBpm,
    this.sleepHours,
    this.weightKg,
    this.bpSysAvg,
    this.bpDiaAvg,
  });
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

    return reports
        .cast<Map<String, dynamic>>()
        .map((r) {
          final id = r['id'] as String;
          return ReportSummary(
            id: id,
            reportedAt: DateTime.parse(r['reported_at'] as String).toLocal(),
            recallWindow: r['recall_window'] as String? ?? 'now',
            source: r['source'] as String? ?? 'self',
            topGrade: topByReport[id] ?? 0,
          );
        })
        .toList(growable: false);
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
                      .inFilter('id', termIds)
                  as List)
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
    }).toList()..sort((a, b) => b.compositeGrade.compareTo(a.compositeGrade));

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

  /// POST /api/reports/generate — returns the structured one-pager report
  /// (RPT-03). Throws on network/API error.
  Future<OnePagerReport> generateOnePager({int days = 14}) async {
    final apiBase = _ref.read(apiBaseUrlProvider);
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      throw StateError('Cannot generate report without an auth session');
    }

    final response = await http
        .post(
          Uri.parse(
            '$apiBase/api/reports/generate?days=$days&include_narrative=true',
          ),
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Report generation failed: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final reportId = body['report_id'] as String? ?? '';
    final report = OnePagerReport.fromJson(
      body['report'] as Map<String, dynamic>,
    );
    return OnePagerReport(
      reportId: reportId,
      generatedAt: report.generatedAt,
      periodDays: report.periodDays,
      heatmapRows: report.heatmapRows,
      worstEpisodes: report.worstEpisodes,
      newOrWorsening: report.newOrWorsening,
      medicationAdherence: report.medicationAdherence,
      vitals: report.vitals,
      narrative: report.narrative,
    );
  }

  Future<String> shareReport(String reportId, {int expiresInDays = 7}) async {
    final apiBase = _ref.read(apiBaseUrlProvider);
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) throw StateError('Not authenticated');

    final response = await http
        .post(
          Uri.parse('$apiBase/api/reports/share'),
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'report_id': reportId,
            'expires_in_days': expiresInDays,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) {
      final err = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        (err['error'] as Map<String, dynamic>?)?['message'] ?? 'Share failed',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['share_url'] as String;
  }
}

/// Group summaries into week buckets, oldest first.
Map<DateTime, List<ReportSummary>> groupByWeek(List<ReportSummary> reports) {
  final out = <DateTime, List<ReportSummary>>{};
  for (final r in reports) {
    final weekStart = _weekStartOf(r.reportedAt);
    out.putIfAbsent(weekStart, () => []).add(r);
  }
  return out;
}

DateTime _weekStartOf(DateTime d) {
  final monday = d.subtract(Duration(days: d.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
}

String weekLabel(DateTime weekStart) {
  final fmt = DateFormat('MMM d');
  return 'Week of ${fmt.format(weekStart)}';
}
