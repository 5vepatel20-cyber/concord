// PostHog initialization.
//
// Privacy posture:
//   - PostHog is always initialized for anonymous event capture on the viral
//     funnel (landing page views, decode attempts). No PHI is ever sent.
//   - `personProfiles: 'identifiedOnly'` — never auto-attach a profile; we
//     only identify after the user explicitly signs in AND has opted in.
//   - Even though PostHog is initialized at startup, `capturePosthogEvent`
//     strips any key that could be PHI (see _phiKey).
//   - Default opt-in is OFF (see settings_storage.dart). The identify call
//     is gated on that toggle.
//   - No PHI in event names or properties. Use generic verbs.
//
// Reference:
//   - posthog_flutter API: https://pub.dev/packages/posthog_flutter

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../config/env.dart';

/// Deny-list for event property keys. Matched case-insensitively so a sloppy
/// caller passing 'Name' or 'SYMPTOM' still gets caught.
final RegExp _phiKey = RegExp(
  r'(name|dob|ssn|mrn|address|condition|medication|symptom|'
  r'full[ _]?name|first[ _]?name|last[ _]?name|'
  r'diagnosis|treatment|provider|phone|email|birth|insurance|policy|'
  r'patient|notes|free[ _]?text|complaint)',
  caseSensitive: false,
);

/// Initializes PostHog for anonymous event capture on the viral funnel.
///
/// Always runs at startup even before the user has opted in, so we can track
/// landing page views and decode attempts. `personProfiles: identifiedOnly`
/// prevents automatic profile creation for anonymous visitors.
///
/// Returns true if PostHog was started, false if the API key is missing.
Future<bool> initPosthog() async {
  final key = AppEnv.posthogApiKey;
  if (key.isEmpty) {
    debugPrint('[posthog] API key empty — analytics disabled.');
    return false;
  }

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
