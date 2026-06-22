// HealthRepository — wraps the `health` plugin for HealthKit (iOS) and
// Health Connect (Android) reads.
//
// HK-01: read-only access to steps, heart rate, sleep, and weight. We
// request the minimum set of metric types we actually use so the OS
// permission sheet matches our privacy posture.
//
// Privacy posture:
//   - Read-only. We never write to Apple Health / Health Connect.
//   - We store nothing on our servers; the snapshot lives in memory only.
//   - Permission can be revoked at any time in iOS Settings → Privacy
//     → Health → Concord.
//
// Reference:
//   - https://pub.dev/packages/health
//   - SPEC.md §"HealthKit reads" (HK-01)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

/// Permission scopes — the union of types we ever request. The OS will
/// show one prompt covering all of these; splitting them later is a
/// follow-up if the prompt becomes confusing.
final List<HealthDataType> _kReadTypes = <HealthDataType>[
  HealthDataType.STEPS,
  HealthDataType.HEART_RATE,
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.WEIGHT,
];

/// One snapshot of "today so far" — what we surface on the home dashboard
/// and what we'd send alongside a symptom report so the care team can
/// correlate trends.
class HealthSnapshot {
  const HealthSnapshot({
    this.steps,
    this.avgHeartRateBpm,
    this.sleepHoursLastNight,
    this.weightKg,
    this.fetchedAt,
  });

  final int? steps;
  final double? avgHeartRateBpm;
  final double? sleepHoursLastNight;
  final double? weightKg;
  final DateTime? fetchedAt;

  bool get isEmpty =>
      steps == null &&
      avgHeartRateBpm == null &&
      sleepHoursLastNight == null &&
      weightKg == null;

  HealthSnapshot copyWith({
    int? steps,
    double? avgHeartRateBpm,
    double? sleepHoursLastNight,
    double? weightKg,
    DateTime? fetchedAt,
  }) =>
      HealthSnapshot(
        steps: steps ?? this.steps,
        avgHeartRateBpm: avgHeartRateBpm ?? this.avgHeartRateBpm,
        sleepHoursLastNight: sleepHoursLastNight ?? this.sleepHoursLastNight,
        weightKg: weightKg ?? this.weightKg,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
}

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository();
});

class HealthRepository {
  HealthRepository();

  final Health _health = Health();
  bool _configured = false;

  /// The `health` plugin only targets iOS (HealthKit) and Android
  /// (Health Connect). On web the calls below would throw, so we surface
  /// a clear UnsupportedError from each entry point instead.
  static bool get _isUnsupportedPlatform => kIsWeb;

  /// Lazy configure. The plugin needs configure() before any other call.
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    if (_isUnsupportedPlatform) return;
    await _health.configure();
    _configured = true;
  }

  /// Returns true if any of the read types are already authorized.
  Future<bool> hasPermission() async {
    if (_isUnsupportedPlatform) return false;
    await _ensureConfigured();
    final granted = await _health.hasPermissions(_kReadTypes) ?? false;
    return granted;
  }

  /// Request read permission for the read-types set. On iOS this surfaces
  /// the system Health sheet; on Android it routes through Health Connect.
  Future<bool> requestPermission() async {
    if (_isUnsupportedPlatform) return false;
    await _ensureConfigured();
    try {
      final granted = await _health.requestAuthorization(_kReadTypes);
      return granted;
    } catch (e) {
      debugPrint('[health] requestAuthorization failed: $e');
      return false;
    }
  }

  /// Fetch today's snapshot. The "today" window is from local midnight to
  /// now; sleep is read from last night (yesterday 6pm → today noon) to
  /// span the overnight gap.
  Future<HealthSnapshot> fetchTodaySnapshot({DateTime? now}) async {
    if (_isUnsupportedPlatform) {
      return HealthSnapshot(fetchedAt: now ?? DateTime.now());
    }
    await _ensureConfigured();
    final n = now ?? DateTime.now();

    // Steps + heart rate + weight: today so far.
    final todayStart = DateTime(n.year, n.month, n.day);
    final todayPoints = await _safeGet(_kReadTypes, todayStart, n);

    // Sleep: previous evening → today's noon, so a nap is captured too.
    final sleepStart = DateTime(n.year, n.month, n.day, 0)
        .subtract(const Duration(hours: 6));
    final sleepEnd = DateTime(n.year, n.month, n.day, 12);
    final sleepPoints =
        await _safeGet([HealthDataType.SLEEP_ASLEEP], sleepStart, sleepEnd);

    return HealthSnapshot(
      steps: _sumNumeric(todayPoints, HealthDataType.STEPS).toInt(),
      avgHeartRateBpm: _averageNumeric(
        todayPoints,
        HealthDataType.HEART_RATE,
      ),
      sleepHoursLastNight: _sumHours(sleepPoints),
      weightKg: _latestNumeric(todayPoints, HealthDataType.WEIGHT),
      fetchedAt: n,
    );
  }

  Future<List<HealthDataPoint>> _safeGet(
    List<HealthDataType> types,
    DateTime start,
    DateTime end,
  ) async {
    try {
      return await _health.getHealthDataFromTypes(
        types: types,
        startTime: start,
        endTime: end,
      );
    } catch (e) {
      debugPrint('[health] getHealthDataFromTypes($types) failed: $e');
      return const [];
    }
  }

  double _sumNumeric(List<HealthDataPoint> pts, HealthDataType type) {
    var sum = 0.0;
    for (final p in pts) {
      if (p.type != type) continue;
      final v = p.value;
      if (v is NumericHealthValue) sum += v.numericValue.toDouble();
    }
    return sum;
  }

  double _averageNumeric(List<HealthDataPoint> pts, HealthDataType type) {
    var sum = 0.0;
    var n = 0;
    for (final p in pts) {
      if (p.type != type) continue;
      final v = p.value;
      if (v is NumericHealthValue) {
        sum += v.numericValue.toDouble();
        n++;
      }
    }
    return n == 0 ? double.nan : sum / n;
  }

  double _latestNumeric(List<HealthDataPoint> pts, HealthDataType type) {
    HealthDataPoint? latest;
    for (final p in pts) {
      if (p.type != type) continue;
      if (latest == null || p.dateTo.isAfter(latest.dateTo)) latest = p;
    }
    final v = latest?.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return double.nan;
  }

  double _sumHours(List<HealthDataPoint> pts) {
    // Sleep points report the duration of an asleep session.
    var totalMs = 0;
    for (final p in pts) {
      totalMs += p.dateTo.difference(p.dateFrom).inMilliseconds;
    }
    return totalMs / Duration.millisecondsPerHour;
  }
}