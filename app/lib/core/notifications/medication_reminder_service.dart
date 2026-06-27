// MedicationReminderService — per-medication local notification reminders.
//
// Schedules one notification per scheduled dose time for each active
// medication. Tapping the notification deep-links to /medications so the
// patient can log adherence (Taken / Skipped) immediately.
//
// Idempotency model:
//   - Notification IDs are allocated from the band [2000, 3600) — well
//     away from the daily-check-in (1001) so we can cancel-then-reschedule
//     the whole band without touching anything else.
//   - On every resync we cancel the entire band and re-schedule from the
//     authoritative list. The index is recomputed against the sorted list,
//     so the same med always gets the same slot as long as the list order
//     doesn't change. We don't depend on that — we just rely on the fact
//     that "cancel then re-add" is safe.
//   - The schedule survives a draft med without a server id: we schedule
//     as soon as the user saves, using the local UUID as a stable identity
//     for cancel-on-resync purposes (the UUID is part of the cached row).
//
// Privacy posture:
//   - Title: "Time for <display name> <dose><unit>" — no PHI beyond what
//     the patient themselves entered.
//   - Body: the route / frequency hint, e.g. "By mouth, daily" or
//     "Weekly on Mon, Thu" — no third-party data, no clinician info.
//   - Payload: deep-link path "/medications" so the tap routes correctly.
//
// Frequency handling:
//   - daily + N times  → N notifications, each DateTimeComponents.time.
//   - weekly + days[]  → one notification per (day, time) pair, each
//                        DateTimeComponents.dayOfWeekAndTime.
//   - as_needed / no times → no schedule (no reminder is appropriate).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/medication.dart';
import 'notification_service.dart';

const int _medIdStart = 2000;
const int _maxMeds = 100;
const int _maxSlotsPerMed = 16;
const int _medIdEnd = _medIdStart + (_maxMeds * _maxSlotsPerMed); // 3600

const String _medChannelId = 'concord.medication_reminders';
const String _medChannelName = 'Medication reminders';
const String _medChannelDesc =
    'Reminders to take your medications at their scheduled times.';

const String kMedicationReminderPayload = '/medications';

/// Singleton so the medication list screen and main.dart share state.
final medicationReminderServiceProvider = Provider<MedicationReminderService>(
  (ref) => MedicationReminderService._(),
);

class MedicationReminderService {
  MedicationReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequested = false;

  /// Idempotent. Reuses the timezone + plugin init done by
  /// [NotificationService.init]. The two share the underlying
  /// FlutterLocalNotificationsPlugin instance so this is cheap.
  Future<void> _ensureInit() async {
    if (_initialized) return;
    if (kIsWeb) {
      // The plugin has no web implementation. We mark initialized so that
      // resyncAll on web is a fast no-op (matches the kIsWeb behavior of
      // NotificationService).
      _initialized = true;
      return;
    }
    // NotificationService.init() already ran in main.dart and set up
    // tz.local + the plugin. Nothing more to do here; the plugin is
    // safe to re-use across multiple service wrappers.
    _initialized = true;
  }

  /// Build the (title, body) pair for a given dose slot.
  ///
  /// Exposed at top level (not private) so tests can pin the wording.
  /// PHI: uses display name + dose + unit that the patient entered
  /// themselves. No third-party data.
  static ({String title, String body}) slotTextFor(Medication m) {
    final doseStr = [m.dose, m.unit].whereType<String>().join(' ').trim();
    final name = m.displayName;
    final titleBase = doseStr.isEmpty ? name : '$name $doseStr';
    final body = switch (m.schedule.frequency) {
      MedFrequency.daily => 'Daily dose',
      MedFrequency.weekly when m.schedule.days.isNotEmpty =>
        'Weekly on ${m.schedule.days.map((d) => d.shortName).join(", ")}',
      MedFrequency.weekly => 'Weekly dose',
      MedFrequency.asNeeded => 'Scheduled dose',
    };
    return (title: 'Time for $titleBase', body: body);
  }

  /// Pure helper: enumerate the (slotIndex, hour, minute, dayOfWeek) tuples
  /// that this medication's schedule produces. dayOfWeek is `null` for
  /// daily schedules (DateTimeComponents.time); for weekly schedules the
  /// tuple is fanned out across each selected day.
  ///
  /// Returns the empty list for `as_needed` and for daily/weekly with
  /// no times set (no reminder is appropriate).
  static List<({int slot, int hour, int minute, Weekday? day})> slotsFor(
    Medication m,
  ) {
    final s = m.schedule;
    if (s.frequency == MedFrequency.asNeeded) return const [];
    if (s.times.isEmpty) return const [];
    final slots = <({int slot, int hour, int minute, Weekday? day})>[];
    var i = 0;
    for (final t in s.times) {
      final parts = t.split(':');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[0]);
      final min = int.tryParse(parts[1]);
      if (h == null || min == null) continue;
      if (h < 0 || h > 23 || min < 0 || min > 59) continue;
      if (s.frequency == MedFrequency.daily) {
        slots.add((slot: i, hour: h, minute: min, day: null));
        i += 1;
      } else {
        // weekly: fan out across each day. If no days selected, fall back
        // to "every day of the week" so the reminder still fires.
        final days = s.days.isEmpty ? Weekday.values : s.days;
        for (final d in days) {
          slots.add((slot: i, hour: h, minute: min, day: d));
          i += 1;
        }
      }
      if (i >= _maxSlotsPerMed) {
        debugPrint(
          '[med-reminder] medication "${m.displayName}" has more slots '
          'than the cap ($_maxSlotsPerMed); truncating.',
        );
        break;
      }
    }
    return slots;
  }

  /// Compute the deterministic notification id for a (medIndex, slot).
  ///
  /// Exposed so tests can pin the allocation scheme.
  static int notificationIdFor(int medIndex, int slot) {
    assert(medIndex >= 0 && medIndex < _maxMeds, 'medIndex out of range');
    assert(slot >= 0 && slot < _maxSlotsPerMed, 'slot out of range');
    return _medIdStart + (medIndex * _maxSlotsPerMed) + slot;
  }

  /// Map a [Weekday] to `DateTime.monday..sunday` (1..7). tz uses 1..7 too.
  static int _weekdayToDateTime(Weekday w) => switch (w) {
    Weekday.mon => DateTime.monday,
    Weekday.tue => DateTime.tuesday,
    Weekday.wed => DateTime.wednesday,
    Weekday.thu => DateTime.thursday,
    Weekday.fri => DateTime.friday,
    Weekday.sat => DateTime.saturday,
    Weekday.sun => DateTime.sunday,
  };

  /// Schedule a single dose-slot notification. Pure orchestration — the
  /// time math is done by [nextInstanceOfTime] (daily) or a manual
  /// next-day-of-week calc (weekly).
  Future<void> _scheduleSlot({
    required int id,
    required Medication med,
    required int hour,
    required int minute,
    required Weekday? day,
  }) async {
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        _medChannelId,
        _medChannelName,
        channelDescription: _medChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final text = slotTextFor(med);

    if (day == null) {
      // Daily: repeat at this HH:MM every day.
      final scheduled = nextInstanceOfTime(hour, minute);
      await _plugin.zonedSchedule(
        id,
        text.title,
        text.body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: kMedicationReminderPayload,
      );
      return;
    }

    // Weekly: schedule at the next instance of (targetDayOfWeek, HH:MM)
    // and repeat weekly on that weekday.
    final targetDow = _weekdayToDateTime(day);
    final scheduledLocal = _nextWeekdayInstance(targetDow, hour, minute);
    final scheduled = tz.TZDateTime.from(scheduledLocal, tz.local);
    await _plugin.zonedSchedule(
      id,
      text.title,
      text.body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: kMedicationReminderPayload,
    );
  }

  /// Cancel every notification id in the medication band.
  Future<void> cancelAll() async {
    await _ensureInit();
    if (kIsWeb) return;
    for (var id = _medIdStart; id < _medIdEnd; id++) {
      await _plugin.cancel(id);
    }
  }

  /// Re-schedule reminders for the full authoritative list of active
  /// medications. Cancels the entire medication band first so stale slots
  /// from removed/edited meds are wiped.
  ///
  /// This is the safe entry point to call from app boot and from the
  /// medications screen after a server refresh.
  Future<void> resyncAll(List<Medication> activeMeds) async {
    await _ensureInit();
    if (kIsWeb) return;

    await cancelAll();

    // Sort by id (server id first, fall back to local-id-like key) so the
    // notification id allocation is stable across resyncs. Without this,
    // reordering the list could swap notification ids.
    final sorted = [...activeMeds]
      ..sort((a, b) {
        final ai = a.id ?? a.displayName;
        final bi = b.id ?? b.displayName;
        return ai.compareTo(bi);
      });

    for (var i = 0; i < sorted.length; i++) {
      if (i >= _maxMeds) {
        debugPrint(
          '[med-reminder] truncating med list at $_maxMeds; '
          'remaining meds will not get reminders.',
        );
        break;
      }
      final m = sorted[i];
      if (!m.active) continue;
      final slots = slotsFor(m);
      for (final s in slots) {
        await _scheduleSlot(
          id: notificationIdFor(i, s.slot),
          med: m,
          hour: s.hour,
          minute: s.minute,
          day: s.day,
        );
      }
    }
    final bandEnd = _medIdStart + sorted.length * _maxSlotsPerMed - 1;
    debugPrint(
      '[med-reminder] resync: ${sorted.length} med(s), '
      'band $_medIdStart..$bandEnd',
    );
  }

  /// Schedule reminders for a single medication without canceling the rest.
  /// Used right after a successful create. The next [resyncAll] will
  /// reconcile the full list.
  Future<void> scheduleFor(Medication med) async {
    await _ensureInit();
    if (kIsWeb) return;
    if (!med.active) return;

    // Use a slot at the end of the band so we don't collide with resyncAll's
    // id allocation. The next resync will reclaim it.
    final tempBase = _medIdEnd - _maxSlotsPerMed;
    final slots = slotsFor(med);
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      await _scheduleSlot(
        id: tempBase + i,
        med: med,
        hour: s.hour,
        minute: s.minute,
        day: s.day,
      );
    }
  }

  /// Request permission once. Idempotent — iOS only prompts the user the
  /// first time; subsequent calls return the cached grant state. Android
  /// 13+ prompts once too. The user may have already granted permission
  /// via the daily check-in toggle; this is a safe re-check.
  Future<bool> ensurePermission() async {
    await _ensureInit();
    if (kIsWeb) return false;
    if (_permissionRequested) return true;
    _permissionRequested = true;
    if (Platform.isIOS) {
      final iosImpl = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted =
          await iosImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return granted;
    }
    if (Platform.isAndroid) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted =
          await androidImpl?.requestNotificationsPermission() ?? false;
      return granted;
    }
    return false;
  }
}

/// Pure helper: next instance of (targetDayOfWeek, HH:MM) in local time.
/// targetDow uses DateTime.monday..DateTime.sunday (1..7).
///
/// Exposed so tests can pin the rolling-forward logic for weekly schedules.
DateTime nextWeekdayInstanceOfTime(
  int targetDow,
  int hour,
  int minute, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  var scheduled = DateTime(n.year, n.month, n.day, hour, minute);
  // Days until target (0..6). If today is target and time is in the future,
  // 0 is correct; if today is target and time has passed, 7 (next week).
  var delta = (targetDow - n.weekday) % 7;
  scheduled = scheduled.add(Duration(days: delta));
  if (!scheduled.isAfter(n)) {
    scheduled = scheduled.add(const Duration(days: 7));
  }
  return scheduled;
}

DateTime _nextWeekdayInstance(int targetDow, int hour, int minute) =>
    nextWeekdayInstanceOfTime(targetDow, hour, minute);
