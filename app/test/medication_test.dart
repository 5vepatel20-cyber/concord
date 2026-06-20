// Tests for Medication + AdherenceEvent JSON round-trip + schedule helper.

import 'package:flutter_test/flutter_test.dart';
import 'package:concord/data/models/medication.dart';

void main() {
  group('Medication', () {
    test('round-trips through JSON with full schedule', () {
      final m = Medication(
        id: 'med-1',
        displayName: 'Tamoxifen',
        dose: '20',
        unit: 'mg',
        route: MedRoute.oral,
        schedule: const MedSchedule(
          frequency: MedFrequency.daily,
          times: ['08:00', '20:00'],
        ),
        active: true,
      );
      final j = m.toJson();
      final back = Medication.fromJson(j);
      expect(back.id, 'med-1');
      expect(back.displayName, 'Tamoxifen');
      expect(back.dose, '20');
      expect(back.unit, 'mg');
      expect(back.route, MedRoute.oral);
      expect(back.schedule.frequency, MedFrequency.daily);
      expect(back.schedule.times, ['08:00', '20:00']);
      expect(back.summary, contains('Tamoxifen'));
      expect(back.summary, contains('20 mg'));
      expect(back.summary, contains('08:00'));
    });

    test('route enum round-trip uses wire values, including sub_q', () {
      expect(MedRouteX.fromWire('sub_q'), MedRoute.subQ);
      expect(MedRoute.subQ.wireValue, 'sub_q');
      expect(MedRouteX.fromWire('nonsense'), MedRoute.other);
    });

    test('summary renders as-needed without times', () {
      final m = Medication(
        id: 'med-2',
        displayName: 'Ondansetron',
        dose: '4',
        unit: 'mg',
        schedule: const MedSchedule(frequency: MedFrequency.asNeeded),
      );
      expect(m.summary, contains('Ondansetron'));
      expect(m.summary, contains('as needed'));
      expect(m.summary, isNot(contains('at ')));
    });

    test('summary renders weekly schedule with days and times', () {
      final m = Medication(
        id: 'med-3',
        displayName: 'Methotrexate',
        schedule: const MedSchedule(
          frequency: MedFrequency.weekly,
          days: [Weekday.mon, Weekday.thu],
          times: ['09:00'],
        ),
      );
      expect(m.summary, contains('weekly'));
      expect(m.summary, contains('09:00'));
    });

    test('omits empty optional fields from JSON', () {
      final m = Medication(id: 'med-4', displayName: 'Aspirin');
      final j = m.toJson();
      expect(j.containsKey('dose'), false);
      expect(j.containsKey('unit'), false);
      expect(j.containsKey('rxnorm_code'), false);
      expect(j['display_name'], 'Aspirin');
    });
  });

  group('AdherenceEvent', () {
    test('round-trips status and timestamps', () {
      final e = AdherenceEvent(
        medicationId: 'med-1',
        scheduledFor: DateTime.utc(2026, 6, 19, 8, 0),
        status: AdherenceStatus.taken,
        loggedAt: DateTime.utc(2026, 6, 19, 8, 5),
      );
      // Round-trip via toJson: note that medication_id is the URL path
      // param, NOT in the request body, so it's not preserved by
      // toJson. We assert that explicitly.
      final back = AdherenceEvent.fromJson(e.toJson());
      expect(back.status, AdherenceStatus.taken);
      expect(back.scheduledFor.toIso8601String(), e.scheduledFor.toIso8601String());
      expect(back.loggedAt?.toIso8601String(), e.loggedAt!.toIso8601String());
    });

    test('fromJson preserves medication_id from server response', () {
      // Server response includes medication_id (it's a join column on
      // medication_event). The request body does NOT.
      final back = AdherenceEvent.fromJson({
        'medication_id': 'med-1',
        'status': 'taken',
        'scheduled_for': '2026-06-19T08:00:00Z',
        'logged_at': '2026-06-19T08:05:00Z',
        'id': 'evt-1',
      });
      expect(back.medicationId, 'med-1');
      expect(back.status, AdherenceStatus.taken);
    });

    test('maps all four wire statuses to/from enum', () {
      for (final s in AdherenceStatus.values) {
        expect(AdherenceStatusX.fromWire(s.wireValue), s);
      }
    });
  });

  group('Schedule JSON', () {
    test('omits empty times/days from wire format', () {
      const s = MedSchedule(frequency: MedFrequency.asNeeded);
      final j = s.toJson();
      expect(j['frequency'], 'as_needed');
      expect(j.containsKey('times'), false);
      expect(j.containsKey('days'), false);
    });

    test('emits days as wire strings when set', () {
      const s = MedSchedule(
        frequency: MedFrequency.weekly,
        days: [Weekday.mon, Weekday.wed],
      );
      final j = s.toJson();
      expect(j['days'], ['mon', 'wed']);
    });
  });
}
