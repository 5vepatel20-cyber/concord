// App entry point.
//
// 1. Load .env at startup so AppEnv can read it.
// 2. Assert we're not shipping the Supabase service_role key by accident.
// 3. Initialize Sentry (with PHI scrubber) — wraps everything below.
// 4. Initialize Supabase (session persistence + JWT refresh handled by SDK).
// 5. Initialize PostHog if the user has opted in (gated on settings).
// 6. Run the app inside ProviderScope so Riverpod is available everywhere.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/monitoring/posthog_init.dart';
import 'core/monitoring/sentry_init.dart';
import 'core/notifications/notification_service.dart';
import 'core/sync/sync_service.dart';
import 'data/supabase/supabase_provider.dart';
import 'features/profile/settings_storage.dart';

Future<void> main() async {
  // Sentry is initialized first so it captures anything that goes wrong
  // during the rest of the boot sequence (dotenv load, env asserts, Supabase
  // init, PostHog init). SentryWidgetsFlutterBinding is set up inside
  // initSentry(), which also calls our `runner` (the rest of main()).
  await initSentry(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await dotenv.load(fileName: '.env');
    AppEnv.assertSafe();

    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      publishableKey: AppEnv.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );

    // PostHog: opt-in only, no-op until the user toggles it on.
    // Runs after Supabase so we can read the same SharedPreferences the
    // settings controller will later watch.
    await initPosthogIfOptedIn();

    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(Supabase.instance.client),
      ],
    );

    // Start the sync service eagerly — it listens to connectivity + auth
    // state and drains the offline queue whenever conditions allow.
    container.read(syncServiceProvider);

    // Initialize the notification plugin and re-schedule the daily check-in
    // if it was previously enabled. We don't request permission here —
    // that's triggered by the user toggling the setting in Profile.
    final notif = container.read(notificationServiceProvider);
    await notif.init();
    final settings = await container.read(settingsControllerProvider.future);
    if (settings.dailyCheckInEnabled) {
      await notif.scheduleDailyCheckIn(
        time: settings.dailyCheckInTime,
        enabled: true,
      );
    }

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const ConcordApp(),
      ),
    );
  });
}
