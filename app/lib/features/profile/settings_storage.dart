// Settings — local-only user preferences backed by SharedPreferences (we add
// the dep in pubspec). For Phase 1.0 we persist:
//   - posthog_opt_in (default false)
//   - onboarding_consent_version (set when the user accepts the disclaimer)
//   - daily_check_in_enabled + daily_check_in_hour + daily_check_in_minute
//     (the SYM-03 reminder)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notifications/notification_service.dart';

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

class SettingsState {
  const SettingsState({
    this.posthogOptIn = false,
    this.consentVersion,
    this.dailyCheckInEnabled = false,
    this.dailyCheckInTime = TimeOfDayHHMM.defaultCheckInTime,
  });

  final bool posthogOptIn;
  final String? consentVersion;
  final bool dailyCheckInEnabled;
  final TimeOfDayHHMM dailyCheckInTime;

  SettingsState copyWith({
    bool? posthogOptIn,
    String? consentVersion,
    bool? dailyCheckInEnabled,
    TimeOfDayHHMM? dailyCheckInTime,
  }) => SettingsState(
    posthogOptIn: posthogOptIn ?? this.posthogOptIn,
    consentVersion: consentVersion ?? this.consentVersion,
    dailyCheckInEnabled: dailyCheckInEnabled ?? this.dailyCheckInEnabled,
    dailyCheckInTime: dailyCheckInTime ?? this.dailyCheckInTime,
  );
}

class SettingsController extends AsyncNotifier<SettingsState> {
  static const _kPosthog = 'posthog_opt_in';
  static const _kConsent = 'onboarding_consent_version';
  static const _kCheckInEnabled = 'daily_check_in_enabled';
  static const _kCheckInHour = 'daily_check_in_hour';
  static const _kCheckInMinute = 'daily_check_in_minute';

  @override
  Future<SettingsState> build() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    return SettingsState(
      posthogOptIn: prefs.getBool(_kPosthog) ?? false,
      consentVersion: prefs.getString(_kConsent),
      dailyCheckInEnabled: prefs.getBool(_kCheckInEnabled) ?? false,
      dailyCheckInTime: TimeOfDayHHMM(
        prefs.getInt(_kCheckInHour) ?? TimeOfDayHHMM.defaultCheckInTime.hour,
        prefs.getInt(_kCheckInMinute) ??
            TimeOfDayHHMM.defaultCheckInTime.minute,
      ),
    );
  }

  Future<void> setPosthogOptIn(bool v) async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setBool(_kPosthog, v);
    state = AsyncData(state.requireValue.copyWith(posthogOptIn: v));
  }

  Future<void> setConsentVersion(String v) async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(_kConsent, v);
    state = AsyncData(state.requireValue.copyWith(consentVersion: v));
  }

  /// Enable / disable the daily check-in. Triggers a permission request
  /// and (re)schedules the notification accordingly.
  Future<void> setDailyCheckInEnabled(bool enabled) async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setBool(_kCheckInEnabled, enabled);

    final notif = ref.read(notificationServiceProvider);
    if (enabled) {
      final granted = await notif.requestPermission();
      if (!granted) {
        // Don't persist the opt-in if the OS denied.
        await prefs.setBool(_kCheckInEnabled, false);
        state = AsyncData(
          state.requireValue.copyWith(dailyCheckInEnabled: false),
        );
        return;
      }
    }
    final s = state.requireValue;
    await notif.scheduleDailyCheckIn(
      time: s.dailyCheckInTime,
      enabled: enabled,
    );
    state = AsyncData(
      state.requireValue.copyWith(dailyCheckInEnabled: enabled),
    );
  }

  Future<void> setDailyCheckInTime(TimeOfDayHHMM time) async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setInt(_kCheckInHour, time.hour);
    await prefs.setInt(_kCheckInMinute, time.minute);

    final s = state.requireValue;
    if (s.dailyCheckInEnabled) {
      await ref
          .read(notificationServiceProvider)
          .scheduleDailyCheckIn(time: time, enabled: true);
    }
    state = AsyncData(state.requireValue.copyWith(dailyCheckInTime: time));
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
      SettingsController.new,
    );
