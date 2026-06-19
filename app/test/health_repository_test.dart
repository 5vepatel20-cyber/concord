// Tests for the HealthSnapshot value object (HK-01).
//
// The plugin itself isn't exercised here; the snapshot mappers are pure
// functions of HealthDataPoint lists, and getting them right is what
// determines whether the home dashboard shows correct numbers.

import 'package:concord/core/health/health_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthSnapshot', () {
    test('isEmpty when nothing is populated', () {
      const s = HealthSnapshot();
      expect(s.isEmpty, isTrue);
    });

    test('isEmpty when any single field is set', () {
      expect(const HealthSnapshot(steps: 100).isEmpty, isFalse);
      expect(const HealthSnapshot(avgHeartRateBpm: 72).isEmpty, isFalse);
      expect(const HealthSnapshot(sleepHoursLastNight: 7.5).isEmpty, isFalse);
      expect(const HealthSnapshot(weightKg: 65).isEmpty, isFalse);
    });

    test('copyWith updates only specified fields', () {
      const s = HealthSnapshot(steps: 100, avgHeartRateBpm: 72);
      final s2 = s.copyWith(sleepHoursLastNight: 7.5);
      expect(s2.steps, 100);
      expect(s2.avgHeartRateBpm, 72);
      expect(s2.sleepHoursLastNight, 7.5);
      expect(s2.weightKg, isNull);
    });
  });
}