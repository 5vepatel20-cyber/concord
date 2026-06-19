// Supabase client provider. The client is initialized once in main.dart and
// shared everywhere via Riverpod. Session persistence + JWT refresh is handled
// transparently by supabase_flutter.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

/// Initialized in main() before runApp().
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  throw StateError(
    'supabaseClientProvider accessed before Supabase.initializeApp(). '
    'Make sure main() awaits Supabase.initializeWith() before runApp().',
  );
});

/// Stream of auth state changes. Emits on sign-in, sign-out, token refresh.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Current session, or null if signed out.
final currentSessionProvider = Provider<Session?>((ref) {
  return ref.watch(supabaseClientProvider).auth.currentSession;
});

/// Current user, or null if signed out.
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

/// Convenience: the API base URL for our Node/TS backend.
final apiBaseUrlProvider = Provider<String>((_) => AppEnv.apiBaseUrl);
