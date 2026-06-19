// Env loader. Reads `.env` at build time via flutter_dotenv.
// CRITICAL: must guard against accidentally bundling the SUPABASE_SERVICE_ROLE_KEY
// (which bypasses RLS). The anon key is JWT-shaped; service_role key contains "service_role".

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AppEnv {
  AppEnv._();

  static String get supabaseUrl =>
      _required('SUPABASE_URL', expectedPrefix: 'https://');

  static String get supabaseAnonKey =>
      _required('SUPABASE_ANON_KEY', expectedPrefix: 'eyJ');

  static String get apiBaseUrl =>
      _required('API_BASE_URL', expectedPrefix: 'https://');

  static String get sentryDsnIos => dotenv.maybeGet('SENTRY_DSN_IOS') ?? '';

  static String get posthogApiKey => dotenv.maybeGet('POSTHOG_API_KEY') ?? '';

  static String get posthogHost =>
      dotenv.maybeGet('POSTHOG_HOST') ?? 'https://us.i.posthog.com';

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

  static String _required(String name, {required String expectedPrefix}) {
    final v = dotenv.maybeGet(name);
    if (v == null || v.isEmpty) {
      throw StateError(
        'Missing required env var "$name". '
        'Copy .env.example to .env and fill it in.',
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
