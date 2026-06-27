// Re-engagement notification service.
//
// Schedules a gentle nudge notification if the user hasn't logged a symptom
// in >48 hours. Resets on each new log entry.
//
// Uses SharedPreferences to persist the last-logged timestamp so the check
// survives app restarts.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

const String _kLastLogKey = 'reengagement_last_log_ts';
const int _reengagementId = 1002;
const String _channelId = 'concord.reengagement';
const String _channelName = 'Re-engagement';
const String _channelDesc = 'Gentle reminders to check in.';
const String _kPayload = '/home';

/// Hours of inactivity before firing a nudge.
const int kReengagementHours = 48;

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

/// Call after every symptom log to reset the re-engagement window.
Future<void> recordSymptomLog() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastLogKey, DateTime.now().millisecondsSinceEpoch);
  await _cancelReengagement();
  debugPrint('[reengagement] log recorded, pending nudge cancelled');
}

/// Schedule a re-engagement notification [kReengagementHours] from now.
/// Called at app startup.
Future<void> scheduleReengagementIfNeeded() async {
  if (kIsWeb) return;

  final prefs = await SharedPreferences.getInstance();
  final lastLogMs = prefs.getInt(_kLastLogKey);
  if (lastLogMs == null) {
    // First-time user — no logs yet. Don't nudge, but do schedule a
    // nudge for later if they still haven't logged.
    final firstNudge = DateTime.now().add(
      const Duration(hours: kReengagementHours),
    );
    await _scheduleAt(firstNudge);
    debugPrint(
      '[reengagement] first-time user, nudge scheduled for $firstNudge',
    );
    return;
  }

  final lastLog = DateTime.fromMillisecondsSinceEpoch(lastLogMs);
  final elapsed = DateTime.now().difference(lastLog);
  final threshold = const Duration(hours: kReengagementHours);

  if (elapsed >= threshold) {
    // Already past threshold — fire now if not already scheduled today.
    // Use a cooldown so we don't spam every boot.
    final lastNudgeMs = prefs.getInt('reengagement_last_nudge_ts');
    if (lastNudgeMs != null) {
      final lastNudge = DateTime.fromMillisecondsSinceEpoch(lastNudgeMs);
      if (DateTime.now().difference(lastNudge).inDays < 1) return;
    }
    await _fireNow(prefs);
  } else {
    // Schedule for when the threshold is reached.
    final nudgeAt = lastLog.add(threshold);
    await _scheduleAt(nudgeAt);
    debugPrint('[reengagement] nudge scheduled for $nudgeAt');
  }
}

Future<void> _scheduleAt(DateTime when) async {
  if (kIsWeb) return;

  await _plugin.cancel(_reengagementId);

  const androidDetails = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDesc,
    importance: Importance.low,
    priority: Priority.low,
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: false,
    presentSound: false,
  );
  const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await _plugin.schedule(
    _reengagementId,
    'How have you been?',
    'It\'s been a while. Tap to check in and log how you\'re feeling.',
    when,
    details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    payload: _kPayload,
  );
}

Future<void> _fireNow(SharedPreferences prefs) async {
  if (kIsWeb) return;

  const androidDetails = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDesc,
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: false,
    presentSound: false,
  );
  const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await _plugin.show(
    _reengagementId,
    'How have you been?',
    'It\'s been a while. Tap to check in and log how you\'re feeling.',
    details,
    payload: _kPayload,
  );

  await prefs.setInt(
    'reengagement_last_nudge_ts',
    DateTime.now().millisecondsSinceEpoch,
  );
  debugPrint('[reengagement] nudge fired');
}

Future<void> _cancelReengagement() async {
  if (kIsWeb) return;
  await _plugin.cancel(_reengagementId);
}
