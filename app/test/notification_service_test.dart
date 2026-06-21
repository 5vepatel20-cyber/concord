// Tests for the notification scheduling logic (SYM-03).
//
// The plugin itself is not exercised here — only the pure-function helper
// that decides "when does the next check-in fire". That helper is the
// one piece of business logic with off-by-one risk (scheduling "today at
// 8pm" when it's already 9pm).

import 'package:concord/core/notifications/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  group('TimeOfDayHHMM', () {
    test('default check-in is 20:00', () {
      expect(TimeOfDayHHMM.defaultCheckInTime.hour, 20);
      expect(TimeOfDayHHMM.defaultCheckInTime.minute, 0);
    });

    test('toString zero-pads HH:MM', () {
      expect(const TimeOfDayHHMM(8, 5).toString(), '08:05');
      expect(const TimeOfDayHHMM(20, 0).toString(), '20:00');
    });

    test('equality is value-based', () {
      expect(const TimeOfDayHHMM(8, 30), const TimeOfDayHHMM(8, 30));
      expect(const TimeOfDayHHMM(8, 30), isNot(const TimeOfDayHHMM(8, 31)));
    });
  });

  group('nextInstanceOfTime', () {
    test('schedules later today when target is in the future', () {
      final now = DateTime.utc(2026, 6, 19, 9, 0);
      final next = nextInstanceOfTime(20, 0, now: now);
      expect(next.year, 2026);
      expect(next.month, 6);
      expect(next.day, 19);
      expect(next.hour, 20);
      expect(next.minute, 0);
    });

    test('rolls to tomorrow when target already passed today', () {
      final now = DateTime.utc(2026, 6, 19, 21, 0);
      final next = nextInstanceOfTime(20, 0, now: now);
      expect(next.day, 20);
      expect(next.hour, 20);
    });

    test('rolls to tomorrow when target is exactly now', () {
      final now = DateTime.utc(2026, 6, 19, 20, 0);
      final next = nextInstanceOfTime(20, 0, now: now);
      expect(next.day, 20);
    });

    test('handles month boundary', () {
      final now = DateTime.utc(2026, 6, 30, 23, 30);
      final next = nextInstanceOfTime(8, 0, now: now);
      expect(next.month, 7);
      expect(next.day, 1);
      expect(next.hour, 8);
    });
  });

  group('tapStream', () {
    // We don't exercise the underlying plugin — just the broadcast
    // behavior of [tapStream]. The router listens to it for warm-start
    // deep links; the contract is "every emitted payload corresponds
    // to a tap that should route the user to that path".

    test('is broadcast — multiple listeners can subscribe at once', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final svc = container.read(notificationServiceProvider);
      expect(svc.tapStream.isBroadcast, true);
    });

    test('exposes the daily check-in payload as a path', () {
      // The router is hard-wired to this string; pinning it in a test
      // catches accidental renames.
      expect(kDailyCheckInPayload, '/log');
      expect(kDailyCheckInPayload.startsWith('/'), true);
    });

    test('ProviderContainer resolves the service without error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final svc = container.read(notificationServiceProvider);
      expect(svc, isNotNull);
    });
  });
}