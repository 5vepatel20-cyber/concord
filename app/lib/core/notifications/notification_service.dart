// NotificationService — daily check-in reminder + permission handling.
//
// SYM-03: A single repeating local notification that fires once per day at
// the user-chosen wall-clock time ("How are you feeling today?"). Tapping
// the notification deep-links to /log so the patient lands directly in
// the quick-log sheet.
//
// Idempotency:
//   - Rescheduling with the same id replaces the existing schedule.
//   - Cancelling with [cancelDailyCheckIn] removes it.
//   - On app boot (or on settings change) we re-call [scheduleDailyCheckIn]
//     which is safe to repeat.
//
// Privacy posture:
//   - No PHI in the notification body. Title and body are static strings.
//   - The payload is a deep-link path ("/log") only.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const int _dailyCheckInId = 1001;
const String _channelId = 'concord.daily_check_in';
const String _channelName = 'Daily check-in';
const String _channelDesc =
    'A daily reminder to log how you are feeling.';

const String kDailyCheckInPayload = '/log';

/// State holder + cache for the plugin. Riverpod provides the singleton so
/// the settings screen and main.dart share the same instance.
final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService._());

class NotificationService {
  NotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  NotificationAppLaunchDetails? _launchDetails;

  /// Returns the payload of the notification that launched the app (if any).
  /// Used by main.dart to navigate to the right screen on cold start.
  String? get initialPayload => _launchDetails?.notificationResponse?.payload;

  /// Initialize the plugin. Safe to call multiple times — only the first
  /// call does work.
  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    // Best-effort: pick the device's local zone. Falls back to UTC if
    // flutter_native_timezone isn't available (we'd add that later).
    try {
      final localName = DateTime.now().timeZoneName;
      // Common short-name → IANA fallback table. tz doesn't accept
      // abbreviations, so we map the most common ones.
      final mapped = _mapTimezoneAbbrev(localName);
      if (mapped != null) tz.setLocalLocation(tz.getLocation(mapped));
    } catch (e) {
      debugPrint('[notif] timezone setup fell back to UTC: $e');
      tz.setLocalLocation(tz.UTC);
    }

    const iosInit = DarwinInitializationSettings(
      // Asking for permission is a separate runtime call (requestPermission),
      // not part of init.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
      iOS: iosInit,
      android: androidInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onTap,
    );
    // Separately fetch launch details (for cold-start deep links).
    _launchDetails = await _plugin.getNotificationAppLaunchDetails();
    _initialized = true;
  }

  /// Request permission for notifications. iOS shows the system dialog;
  /// Android 13+ shows the runtime permission dialog. Returns true if
  /// granted, false otherwise.
  Future<bool> requestPermission() async {
    if (!_initialized) await init();

    if (Platform.isIOS) {
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return granted;
    }
    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission() ??
          false;
      return granted;
    }
    return false;
  }

  /// Schedule (or replace) the daily check-in at [time]. The notification
  /// fires every day at HH:MM in the device's local timezone.
  Future<void> scheduleDailyCheckIn({
    required TimeOfDayHHMM time,
    required bool enabled,
  }) async {
    if (!_initialized) await init();
    await _plugin.cancel(_dailyCheckInId);

    if (!enabled) {
      debugPrint('[notif] daily check-in disabled — cleared.');
      return;
    }

    final scheduled = _nextInstanceOf(time.hour, time.minute);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      _dailyCheckInId,
      'How are you feeling today?',
      'A quick check-in helps your care team see trends.',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: kDailyCheckInPayload,
    );
    debugPrint('[notif] scheduled daily check-in for $scheduled');
  }

  Future<void> cancelDailyCheckIn() async {
    if (!_initialized) await init();
    await _plugin.cancel(_dailyCheckInId);
  }

  void _onTap(NotificationResponse response) {
    // The actual navigation happens at the router level via
    // [initialPayload] (cold start) or a stream we expose here (warm start).
    // For 1.0 we just log; the settings screen re-reads [initialPayload]
    // on next build and routes from there.
    debugPrint('[notif] tapped: payload=${response.payload}');
  }
}

/// Plain time-of-day without the Flutter material import (keeps this layer
/// platform-neutral and trivially unit-testable).
class TimeOfDayHHMM {
  const TimeOfDayHHMM(this.hour, this.minute);
  final int hour;
  final int minute;

  static const defaultCheckInTime = TimeOfDayHHMM(20, 0); // 8pm

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is TimeOfDayHHMM && other.hour == hour && other.minute == minute;
  @override
  int get hashCode => Object.hash(hour, minute);
}

/// Build the next `tz.TZDateTime` at the given local HH:MM. Pure function —
/// exported so tests can hit it directly.
///
/// Edge case: if HH:MM has already passed (or is exactly now), we roll
/// forward to tomorrow. Firing "right now" would be useless — the user
/// just opened the app, they don't need a notification immediately.
tz.TZDateTime nextInstanceOfTime(int hour, int minute, {DateTime? now}) {
  final n = now ?? tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local,
    n.year,
    n.month,
    n.day,
    hour,
    minute,
  );
  if (!scheduled.isAfter(n)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

tz.TZDateTime _nextInstanceOf(int hour, int minute) =>
    nextInstanceOfTime(hour, minute);

/// Map the most common short timezone names to IANA tz database names.
/// Covers the timezones the Concord team operates in; the device is
/// usually already set to one of these.
String? _mapTimezoneAbbrev(String abbrev) {
  switch (abbrev.toUpperCase()) {
    case 'EST':
    case 'EDT':
      return 'America/New_York';
    case 'CST':
    case 'CDT':
      return 'America/Chicago';
    case 'MST':
    case 'MDT':
      return 'America/Denver';
    case 'PST':
    case 'PDT':
      return 'America/Los_Angeles';
    case 'UTC':
    case 'GMT':
      return 'Etc/UTC';
    case 'CET':
    case 'CEST':
      return 'Europe/Paris';
    case 'BST':
      return 'Europe/London';
    case 'IST':
      return 'Asia/Kolkata';
    case 'JST':
      return 'Asia/Tokyo';
    default:
      return null; // fall through to UTC in the caller
  }
}