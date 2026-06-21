// Tests for MedicationReminderService — pure-function helpers only.
//
// We do NOT exercise the flutter_local_notifications plugin directly here
// (it has no usable in-process mock and instrumenting it would couple the
// test to internals). What we DO cover:
//   - the slot enumeration for each frequency (the thing with the most
//     off-by-one risk — weekly × days × times)
//   - the deterministic id allocation
//   - the schedule text composition (privacy-sensitive: PHI rules apply)
//   - the weekly next-instance rolling-forward logic

import 'package:concord/core/notifications/medication_reminder_service.dart';
import 'package:concord/data/models/medication.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slotsFor', () {
    test('daily with two times produces two daily slots', () {
      const m = Medication(
        id: 'm1',
        displayName: 'Tamoxifen',
        schedule: MedSchedule(
          frequency: MedFrequency.daily,
          times: ['08:00', '20:00'],
        ),
      );
      final slots = MedicationReminderService.slotsFor(m);
      expect(slots.length, 2);
      expect(slots[0].hour, 8);
      expect(slots[0].minute, 0);
      expect(slots[0].day, isNull);
      expect(slots[1].hour, 20);
      expect(slots[1].minute, 0);
      expect(slots[1].day, isNull);
    });

    test('weekly fans out across each selected day for each time', () {
      const m = Medication(
        id: 'm2',
        displayName: 'Methotrexate',
        schedule: MedSchedule(
          frequency: MedFrequency.weekly,
          days: [Weekday.mon, Weekday.thu],
          times: ['09:00'],
        ),
      );
      final slots = MedicationReminderService.slotsFor(m);
      expect(slots.length, 2);
      expect(slots[0].day, Weekday.mon);
      expect(slots[1].day, Weekday.thu);
      expect(slots.every((s) => s.hour == 9 && s.minute == 0), true);
    });

    test('weekly with no days selected falls back to all seven days', () {
      const m = Medication(
        id: 'm3',
        displayName: 'Methotrexate',
        schedule: MedSchedule(
          frequency: MedFrequency.weekly,
          days: [],
          times: ['09:00'],
        ),
      );
      final slots = MedicationReminderService.slotsFor(m);
      expect(slots.length, 7);
      expect(
        slots.map((s) => s.day).toSet(),
        Weekday.values.toSet(),
      );
    });

    test('as_needed produces zero slots regardless of times', () {
      const m = Medication(
        id: 'm4',
        displayName: 'Ondansetron',
        schedule: MedSchedule(
          frequency: MedFrequency.asNeeded,
          times: ['08:00', '20:00'],
        ),
      );
      expect(MedicationReminderService.slotsFor(m), isEmpty);
    });

    test('daily with no times produces zero slots', () {
      const m = Medication(
        id: 'm5',
        displayName: 'Aspirin',
        schedule: MedSchedule(frequency: MedFrequency.daily, times: []),
      );
      expect(MedicationReminderService.slotsFor(m), isEmpty);
    });

    test('malformed HH:MM strings are skipped, not crashed', () {
      const m = Medication(
        id: 'm6',
        displayName: 'Mystery',
        schedule: MedSchedule(
          frequency: MedFrequency.daily,
          times: ['nope', '25:99', '08:30', ''],
        ),
      );
      final slots = MedicationReminderService.slotsFor(m);
      expect(slots.length, 1);
      expect(slots[0].hour, 8);
      expect(slots[0].minute, 30);
    });

    test('truncates beyond the per-med slot cap', () {
      // Build a med with 20 daily times; only the first 16 should be kept.
      final times = List.generate(20, (i) {
        final hh = (i ~/ 60).toString().padLeft(2, '0');
        final mm = (i % 60).toString().padLeft(2, '0');
        return '$hh:$mm';
      });
      final m = Medication(
        id: 'm7',
        displayName: 'Mega',
        schedule: MedSchedule(
          frequency: MedFrequency.daily,
          times: times,
        ),
      );
      final slots = MedicationReminderService.slotsFor(m);
      expect(slots.length, 16);
    });
  });

  group('notificationIdFor', () {
    test('first med, first slot → 2000', () {
      expect(MedicationReminderService.notificationIdFor(0, 0), 2000);
    });

    test('first med, second slot → 2001', () {
      expect(MedicationReminderService.notificationIdFor(0, 1), 2001);
    });

    test('second med, first slot → 2016', () {
      expect(MedicationReminderService.notificationIdFor(1, 0), 2016);
    });

    test('band never overlaps daily check-in (1001)', () {
      for (var i = 0; i < 100; i++) {
        for (var j = 0; j < 16; j++) {
          final id = MedicationReminderService.notificationIdFor(i, j);
          expect(id, greaterThan(1001));
          expect(id, lessThan(5000));
        }
      }
    });
  });

  group('slotTextFor (PHI rules)', () {
    test('title includes dose and unit when present', () {
      const m = Medication(
        id: 'm',
        displayName: 'Tamoxifen',
        dose: '20',
        unit: 'mg',
        schedule: MedSchedule(frequency: MedFrequency.daily),
      );
      final t = MedicationReminderService.slotTextFor(m);
      expect(t.title, 'Time for Tamoxifen 20 mg');
      expect(t.body, 'Daily dose');
    });

    test('title omits dose/unit when neither is set', () {
      const m = Medication(
        id: 'm',
        displayName: 'Aspirin',
        schedule: MedSchedule(frequency: MedFrequency.asNeeded),
      );
      final t = MedicationReminderService.slotTextFor(m);
      expect(t.title, 'Time for Aspirin');
    });

    test('weekly body lists selected days in order', () {
      const m = Medication(
        id: 'm',
        displayName: 'Methotrexate',
        schedule: MedSchedule(
          frequency: MedFrequency.weekly,
          days: [Weekday.mon, Weekday.thu],
          times: ['09:00'],
        ),
      );
      final t = MedicationReminderService.slotTextFor(m);
      expect(t.body, 'Weekly on Mon, Thu');
    });

    test('weekly body with no days still says "Weekly dose"', () {
      const m = Medication(
        id: 'm',
        displayName: 'Methotrexate',
        schedule: MedSchedule(
          frequency: MedFrequency.weekly,
          times: ['09:00'],
        ),
      );
      final t = MedicationReminderService.slotTextFor(m);
      expect(t.body, 'Weekly dose');
    });
  });

  group('nextWeekdayInstanceOfTime', () {
    test('target later this week schedules within the same week', () {
      // 2026-06-19 is a Friday (DateTime.friday == 5).
      final now = DateTime(2026, 6, 19, 9, 0); // Fri morning
      final next = nextWeekdayInstanceOfTime(DateTime.monday, 8, 0, now: now);
      expect(next.weekday, DateTime.monday);
      expect(next.day, 22); // Mon
      expect(next.hour, 8);
    });

    test('today at a future time schedules for today', () {
      final now = DateTime(2026, 6, 19, 9, 0); // Fri
      final next = nextWeekdayInstanceOfTime(DateTime.friday, 14, 0, now: now);
      expect(next.weekday, DateTime.friday);
      expect(next.day, 19);
      expect(next.hour, 14);
    });

    test('today at a past time rolls to next week', () {
      final now = DateTime(2026, 6, 19, 14, 0); // Fri 2pm
      final next = nextWeekdayInstanceOfTime(DateTime.friday, 9, 0, now: now);
      expect(next.weekday, DateTime.friday);
      expect(next.day, 26); // next Friday
      expect(next.hour, 9);
    });

    test('past days this week roll to next week', () {
      // Mon
      final now = DateTime(2026, 6, 15, 9, 0); // Mon
      // Thu this week is in the future, so should be 4 days away.
      final thu = nextWeekdayInstanceOfTime(DateTime.thursday, 8, 0, now: now);
      expect(thu.weekday, DateTime.thursday);
      expect(thu.day, 18);
    });

    test('crosses month boundary correctly', () {
      // Last day of June 2026 is a Wednesday. Thursday is July 2.
      final now = DateTime(2026, 6, 30, 23, 30); // Wed
      final thu = nextWeekdayInstanceOfTime(DateTime.thursday, 8, 0, now: now);
      expect(thu.month, 7);
      expect(thu.day, 2);
      expect(thu.weekday, DateTime.thursday);
    });
  });
}
