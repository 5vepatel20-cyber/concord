import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../supabase/supabase_provider.dart';

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository(ref);
});

final healthMetricsProvider = FutureProvider.autoDispose<List<MetricTypeGroup>>(
  (ref) async {
    return ref.read(healthRepositoryProvider).fetchMetrics();
  },
);

class MetricTypeGroup {
  final String type;
  final String label;
  final String unit;
  final String color;
  final int count;
  final num? latest;
  final num? min;
  final num? max;
  final num? avg;
  final List<MetricSample> samples;

  const MetricTypeGroup({
    required this.type,
    required this.label,
    required this.unit,
    required this.color,
    required this.count,
    this.latest,
    this.min,
    this.max,
    this.avg,
    required this.samples,
  });

  factory MetricTypeGroup.fromJson(Map<String, dynamic> j) {
    final rawSamples = (j['samples'] as List<dynamic>?) ?? [];
    return MetricTypeGroup(
      type: j['type'] as String? ?? '',
      label: j['label'] as String? ?? '',
      unit: j['unit'] as String? ?? '',
      color: j['color'] as String? ?? '#888',
      count: j['count'] as int? ?? 0,
      latest: j['latest'] as num?,
      min: j['min'] as num?,
      max: j['max'] as num?,
      avg: j['avg'] as num?,
      samples: rawSamples
          .map((s) => MetricSample.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MetricSample {
  final String id;
  final num value;
  final String unit;
  final String measuredAt;
  final String? source;

  const MetricSample({
    required this.id,
    required this.value,
    required this.unit,
    required this.measuredAt,
    this.source,
  });

  factory MetricSample.fromJson(Map<String, dynamic> j) => MetricSample(
    id: j['id'] as String? ?? '',
    value: j['value'] as num? ?? 0,
    unit: j['unit'] as String? ?? '',
    measuredAt: j['measured_at'] as String? ?? '',
    source: j['source'] as String?,
  );
}

class ReferenceRange {
  final num? low;
  final num? high;
  final String label;

  const ReferenceRange({this.low, this.high, required this.label});
}

ReferenceRange referenceRangeFor(String type, num value) {
  switch (type) {
    case 'hr':
      if (value < 60)
        return const ReferenceRange(low: 60, high: 100, label: 'Low');
      if (value > 100)
        return const ReferenceRange(low: 60, high: 100, label: 'High');
      return const ReferenceRange(low: 60, high: 100, label: 'Normal');
    case 'bp_sys':
      if (value < 90)
        return const ReferenceRange(low: 90, high: 120, label: 'Low');
      if (value > 120)
        return const ReferenceRange(low: 90, high: 120, label: 'High');
      return const ReferenceRange(low: 90, high: 120, label: 'Normal');
    case 'bp_dia':
      if (value < 60)
        return const ReferenceRange(low: 60, high: 80, label: 'Low');
      if (value > 80)
        return const ReferenceRange(low: 60, high: 80, label: 'High');
      return const ReferenceRange(low: 60, high: 80, label: 'Normal');
    case 'glucose':
      if (value < 70)
        return const ReferenceRange(low: 70, high: 140, label: 'Low');
      if (value > 140)
        return const ReferenceRange(low: 70, high: 140, label: 'High');
      return const ReferenceRange(low: 70, high: 140, label: 'Normal');
    case 'weight':
      return const ReferenceRange(label: 'Individual');
    case 'steps':
      return const ReferenceRange(label: 'Goal dependent');
    case 'sleep':
      if (value < 7) return const ReferenceRange(low: 7, high: 9, label: 'Low');
      if (value > 9)
        return const ReferenceRange(low: 7, high: 9, label: 'High');
      return const ReferenceRange(low: 7, high: 9, label: 'Normal');
    default:
      return const ReferenceRange(label: '');
  }
}

class HealthRepository {
  HealthRepository(this._ref);
  final Ref _ref;

  Future<List<MetricTypeGroup>> fetchMetrics({int days = 90}) async {
    final apiBase = _ref.read(apiBaseUrlProvider);
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) throw StateError('Not authenticated');

    final uri = Uri.parse('$apiBase/api/health/metrics?days=$days');
    final res = await http
        .get(uri, headers: {'Authorization': 'Bearer ${session.accessToken}'})
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200)
      throw Exception('Failed to load metrics (${res.statusCode})');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['types'] as List<dynamic>?) ?? [];
    return raw
        .map((t) => MetricTypeGroup.fromJson(t as Map<String, dynamic>))
        .toList();
  }
}
