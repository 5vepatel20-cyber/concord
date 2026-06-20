// Env loader. Reads from `--dart-define` first (works on web + production),
// then falls back to `.env` via flutter_dotenv (works on native dev).
// CRITICAL: must guard against accidentally bundling the SUPABASE_SERVICE_ROLE_KEY
// (which bypasses RLS). The anon key is JWT-shaped; service_role key contains "service_role".

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AppEnv {
  AppEnv._();

  static String get supabaseUrl => _required(
        'SUPABASE_URL',
        const String.fromEnvironment('SUPABASE_URL'),
        expectedPrefix: 'https://',
      );

  static String get supabaseAnonKey => _required(
        'SUPABASE_ANON_KEY',
        const String.fromEnvironment('SUPABASE_ANON_KEY'),
        expectedPrefix: 'eyJ',
      );

  static String get apiBaseUrl => _required(
        'API_BASE_URL',
        const String.fromEnvironment('API_BASE_URL'),
        expectedPrefix: 'https://',
      );

  static String get sentryDsnIos =>
      const String.fromEnvironment('SENTRY_DSN_IOS').isNotEmpty
          ? const String.fromEnvironment('SENTRY_DSN_IOS')
          : (dotenv.maybeGet('SENTRY_DSN_IOS') ?? '');

  static String get posthogApiKey =>
      const String.fromEnvironment('POSTHOG_API_KEY').isNotEmpty
          ? const String.fromEnvironment('POSTHOG_API_KEY')
          : (dotenv.maybeGet('POSTHOG_API_KEY') ?? '');

  static String get posthogHost {
    const fromDefine = String.fromEnvironment('POSTHOG_HOST');
    if (fromDefine.isNotEmpty) return fromDefine;
    return dotenv.maybeGet('POSTHOG_HOST') ?? 'https://us.i.posthog.com';
  }

  /// Belt-and-suspenders guard. Runs once at app boot. If a developer accidentally
  /// pastes the service_role key into SUPABASE_ANON_KEY, this throws at startup
  /// instead of leaking to clients.
  static void assertSafe() {
    final key = supabaseAnonKey;
    assert(
      !key.toLowerCase().contains('service_role'),
      'SUPABASE_ANON_KEY looks like the service_role key — '
      'service_role bypasses RLS and must NEVER ship in the client.',
    );
    assert(
      key.startsWith('eyJ'),
      'SUPABASE_ANON_KEY is not a JWT — expected to start with "eyJ".',
    );
    if (kDebugMode) {
      debugPrint('[env] SUPABASE_URL: $supabaseUrl');
      debugPrint('[env] API_BASE_URL: $apiBaseUrl');
      debugPrint('[env] SENTRY_DSN_IOS: ${sentryDsnIos.isNotEmpty ? "<set>" : "<empty>"}');
      debugPrint('[env] POSTHOG_API_KEY: ${posthogApiKey.isNotEmpty ? "<set>" : "<empty>"}');
    }
  }

  static String _required(
    String name,
    String fromDefine, {
    required String expectedPrefix,
  }) {
    final v = fromDefine.isNotEmpty
        ? fromDefine
        : (dotenv.maybeGet(name) ?? '');
    if (v.isEmpty) {
      throw StateError(
        'Missing required env var "$name". '
        'Copy .env.example to .env (native) or pass --dart-define=$name=... '
        '(web / production).',
      );
    }
    if (!v.startsWith(expectedPrefix)) {
      throw StateError(
        'Env var "$name" must start with "$expectedPrefix". Got: '
        '${v.substring(0, v.length.clamp(0, 8))}…',
      );
    }
    return v;
  }
}
