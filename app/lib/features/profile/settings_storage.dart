// Settings — local-only user preferences backed by SharedPreferences (we add
// the dep in pubspec). For Phase 1.0 we only persist two values:
//   - posthog_opt_in (default false)
//   - onboarding_consent_version (set when the user accepts the disclaimer)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

class SettingsState {
  const SettingsState({
    this.posthogOptIn = false,
    this.consentVersion,
  });

  final bool posthogOptIn;
  final String? consentVersion;

  SettingsState copyWith({bool? posthogOptIn, String? consentVersion}) =>
      SettingsState(
        posthogOptIn: posthogOptIn ?? this.posthogOptIn,
        consentVersion: consentVersion ?? this.consentVersion,
      );
}

class SettingsController extends AsyncNotifier<SettingsState> {
  static const _kPosthog = 'posthog_opt_in';
  static const _kConsent = 'onboarding_consent_version';

  @override
  Future<SettingsState> build() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    return SettingsState(
      posthogOptIn: prefs.getBool(_kPosthog) ?? false,
      consentVersion: prefs.getString(_kConsent),
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
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);