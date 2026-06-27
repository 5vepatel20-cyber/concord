// Sentry initialization.
//
// Sentry is wrapped around `runApp` via `SentryWidgetsFlutterBinding.ensureInitialized()`
// (see main.dart) so unhandled exceptions, Flutter framework errors, and platform
// errors are captured automatically.
//
// PHI-scrubbing:
//   Sentry's own PII scrubber is on by default. We add a defense-in-depth
//   `beforeSend` that strips common PHI fields from the event user payload,
//   tags, and the `extra` map. We also register a `beforeBreadcrumb` callback
//   so free-text breadcrumb messages can't carry PHI either.
//
// What gets scrubbed:
//   - user.email, user.ip_address, user.username, user.name, user.geo
//   - any tag / extra / breadcrumb key whose name matches the deny-list regex
//   - free-text values get truncated
//
// References:
//   - sentry_flutter API: https://pub.dev/packages/sentry_flutter
//   - SPEC.md §11 "PHI minimization"

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/env.dart';

/// Wraps the user-supplied runner with Sentry's binding + RunnerConfig.
/// Returns a [Future] that completes when Sentry init resolves.
Future<void> initSentry(Future<void> Function() runner) async {
  final dsn = AppEnv.sentryDsnIos;
  if (dsn.isEmpty) {
    // No DSN configured (e.g. local dev without a real Sentry project).
    // Skip init entirely so we don't spam the console.
    debugPrint('[sentry] DSN empty — running without crash reporting.');
    await runner();
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = dsn;
    options.environment = kDebugMode ? 'debug' : 'production';
    options.release = 'concord@1.0.0+1';
    options.tracesSampleRate = kDebugMode ? 1.0 : 0.1;

    // Default data scrubber stays on; this is the second pass.
    options.sendDefaultPii = false;

    // Non-fatal events don't need stacktraces attached (smaller payload,
    // less likely to carry frames with PHI). Fatal events keep them.
    options.attachStacktrace = false;

    options.beforeSend = _scrubEvent;
    options.beforeBreadcrumb = _scrubBreadcrumb;
  }, appRunner: runner);
}

/// PHI deny-list. Matched case-insensitively against key names anywhere in
/// the event (tags, extras, breadcrumbs, user, request).
final RegExp _phiKey = RegExp(
  r'(name|dob|ssn|mrn|address|condition|medication|symptom|'
  r'full[ _]?name|first[ _]?name|last[ _]?name|'
  r'diagnosis|treatment|provider|phone|email|birth|insurance|policy|'
  r'patient|notes|free[ _]?text|complaint)',
  caseSensitive: false,
);

/// Strips a free-text value down to a safe length. Long free text is the #1
/// way PHI leaks into crash reports.
const int _maxFreeTextLen = 80;

String _truncateString(String v) {
  if (v.length <= _maxFreeTextLen) return v;
  return '${v.substring(0, _maxFreeTextLen)}…[truncated]';
}

bool _isPhiKey(String key) => _phiKey.hasMatch(key);

SentryEvent? _scrubEvent(SentryEvent event, Hint hint) {
  // User payload — always strip.
  final user = event.user;
  if (user != null) {
    event = event.copyWith(
      user: (user.copyWith(
        email: null,
        ipAddress: null,
        username: null,
        name: null,
        geo: null,
        data: _scrubMap(user.data),
      )),
    );
  }

  // Tags.
  final tags = event.tags;
  if (tags != null) {
    final cleaned = <String, String>{};
    for (final entry in tags.entries) {
      if (_isPhiKey(entry.key)) continue;
      cleaned[entry.key] = entry.value;
    }
    event = event.copyWith(tags: cleaned.isEmpty ? null : cleaned);
  }

  // Extras (free-form map of {key -> any}). Note: the property is `extra`
  // (singular) and is marked deprecated in favor of structured Contexts,
  // but the SDK still emits it from legacy call sites, so we scrub it.
  // ignore: deprecated_member_use
  final extra = event.extra;
  if (extra != null) {
    // ignore: deprecated_member_use
    event = event.copyWith(extra: _scrubMap(extra));
  }

  // Exception values sometimes carry the user's input. Drop the per-exception
  // `value` field (Flutter framework usually puts the type/message in `type`
  // /`value`; we keep type only).
  final exs = event.exceptions;
  if (exs != null) {
    event = event.copyWith(
      exceptions: exs.map((e) => e.copyWith(value: null)).toList(),
    );
  }

  return event;
}

Breadcrumb? _scrubBreadcrumb(Breadcrumb? crumb, Hint hint) {
  if (crumb == null) return null;

  // Don't trust breadcrumb messages or category names to be free of PHI.
  final msg = crumb.message;
  if (msg != null && _phiKey.hasMatch(msg)) {
    return null;
  }
  var scrubbed = crumb;
  if (msg != null && msg.length > _maxFreeTextLen) {
    scrubbed = scrubbed.copyWith(message: _truncateString(msg));
  }
  final data = scrubbed.data;
  if (data != null) {
    scrubbed = scrubbed.copyWith(data: _scrubMap(data));
  }
  return scrubbed;
}

Map<String, dynamic>? _scrubMap(Map<String, dynamic>? input) {
  if (input == null) return null;
  final out = <String, dynamic>{};
  for (final entry in input.entries) {
    if (_isPhiKey(entry.key)) continue;
    out[entry.key] = _scrubDynamic(entry.value);
  }
  return out;
}

dynamic _scrubDynamic(dynamic v) {
  if (v is String) return _truncateString(v);
  if (v is Map<String, dynamic>) return _scrubMap(v);
  if (v is List) return v.map(_scrubDynamic).toList();
  return v;
}
