// PostHog initialization.
//
// Privacy posture (SPEC.md §11):
//   - `personProfiles: 'identifiedOnly'` — never auto-attach a profile; we
//     only identify after the user explicitly signs in AND has opted in.
//   - Default opt-in is OFF (see settings_storage.dart). Until the user
//     toggles it on, capture is a no-op.
//   - No PHI in event names or properties. Use generic verbs.
//
// Reference:
//   - posthog_flutter API: https://pub.dev/packages/posthog_flutter

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

const String _kPosthogOptIn = 'posthog_opt_in';

/// Deny-list for event property keys. Matched case-insensitively so a sloppy
/// caller passing 'Name' or 'SYMPTOM' still gets caught.
final RegExp _phiKey = RegExp(
  r'(name|dob|ssn|mrn|address|condition|medication|symptom|'
  r'full[ _]?name|first[ _]?name|last[ _]?name|'
  r'diagnosis|treatment|provider|phone|email|birth|insurance|policy|'
  r'patient|notes|free[ _]?text|complaint)',
  caseSensitive: false,
);

/// Reads the opt-in flag directly from SharedPreferences, since this runs at
/// app startup before the Riverpod container exists.
Future<bool> _readPosthogOptIn() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kPosthogOptIn) ?? false;
}

/// Initializes PostHog if the user has opted in. No-op otherwise.
///
/// Returns true if PostHog was started, false if it was skipped.
Future<bool> initPosthogIfOptedIn() async {
  final key = AppEnv.posthogApiKey;
  if (key.isEmpty) {
    debugPrint('[posthog] API key empty — analytics disabled.');
    return false;
  }

  final optedIn = await _readPosthogOptIn();
  if (!optedIn) {
    debugPrint('[posthog] user has not opted in — analytics disabled.');
    return false;
  }

  // The class is `Posthog` (lowercase 'o') per the public package API; the
  // factory constructor returns the singleton. `host` is a public field on
  // PostHogConfig (no named constructor param), so we set it after building.
  await Posthog().setup(
    PostHogConfig(key)
      ..host = AppEnv.posthogHost
      ..personProfiles = PostHogPersonProfiles.identifiedOnly
      ..captureApplicationLifecycleEvents = true
      ..debug = kDebugMode,
  );
  debugPrint('[posthog] initialized at ${AppEnv.posthogHost}');
  return true;
}

/// Identifies the current PostHog profile after sign-in. Called from auth
/// listeners. Pass the userId (always non-PHI) and optionally an email (the
/// user has explicitly opted in by toggling analytics on, so this is allowed).
void identifyPosthogUser(String userId, {String? email}) {
  if (email != null) {
    Posthog().identify(userId: userId, userProperties: {'email': email});
  } else {
    Posthog().identify(userId: userId);
  }
}

/// Clears the PostHog profile on sign-out so the next user doesn't inherit
/// it on the same device.
void resetPosthogUser() {
  Posthog().reset();
}

/// Captures a generic, non-PHI event. Pass only generic verbs and counts —
/// no symptom names, conditions, dates, free text, or anything that could
/// indirectly identify a patient.
void capturePosthogEvent(String name, {Map<String, Object?>? properties}) {
  // Defensive: strip any property key that *could* be PHI just in case a
  // future caller gets sloppy. Also drop nulls since the SDK signature is
  // non-nullable values.
  final cleaned = <String, Object>{};
  for (final entry in (properties ?? const {}).entries) {
    if (_phiKey.hasMatch(entry.key)) continue;
    if (entry.value == null) continue;
    cleaned[entry.key] = entry.value as Object;
  }
  Posthog().capture(eventName: name, properties: cleaned);
}
