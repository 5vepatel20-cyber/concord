// Auth controller — Riverpod AsyncNotifier wrapping Supabase auth.
// Exposes the current auth state, plus sign-in / sign-up / sign-out methods
// that return Result<T, AppError> for safe composition.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../data/supabase/supabase_provider.dart';

class AuthSessionView {
  const AuthSessionView({
    required this.userId,
    this.email,
    this.emailConfirmed = false,
  });
  final String userId;
  final String? email;
  final bool emailConfirmed;

  bool get isAuthenticated => userId.isNotEmpty;
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSessionView>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSessionView> {
  @override
  Future<AuthSessionView> build() async {
    // Subscribe to auth state changes so the notifier rebuilds on sign-in / out / refresh.
    ref.listen(authStateChangesProvider, (prev, next) {
      _refresh();
    });
    return _snapshot();
  }

  AuthSessionView _snapshot() {
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    final user = session?.user;
    if (session == null || user == null) {
      return const AuthSessionView(userId: '');
    }
    return AuthSessionView(
      userId: user.id,
      email: user.email,
      emailConfirmed: user.emailConfirmedAt != null,
    );
  }

  void _refresh() {
    state = AsyncData(_snapshot());
  }

  Future<Result<AuthSessionView, AppError>> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      final res = await ref
          .read(supabaseClientProvider)
          .auth
          .signInWithPassword(email: email.trim(), password: password);
      final user = res.user;
      if (user == null) {
        return const Err(
          AppError(
            kind: AppErrorKind.server,
            code: 'signin_no_user',
            message: 'Sign-in did not return a user.',
          ),
        );
      }
      final view = AuthSessionView(
        userId: user.id,
        email: user.email,
        emailConfirmed: user.emailConfirmedAt != null,
      );
      state = AsyncData(view);
      return Ok(view);
    } on AuthException catch (e) {
      final err = AppError(
        kind: AppErrorKind.unauthorized,
        code: 'invalid_credentials',
        message: e.message,
      );
      state = AsyncData(_snapshot());
      return Err(err);
    } catch (e) {
      final err = AppError.network(e);
      state = AsyncData(_snapshot());
      return Err(err);
    }
  }

  Future<Result<AuthSessionView, AppError>> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    state = const AsyncLoading();
    try {
      final res = await ref
          .read(supabaseClientProvider)
          .auth
          .signUp(
            email: email.trim(),
            password: password,
            data: {
              if (fullName != null && fullName.isNotEmpty)
                'full_name': fullName,
            },
          );
      final user = res.user;
      if (user == null) {
        return const Err(
          AppError(
            kind: AppErrorKind.server,
            code: 'signup_no_user',
            message: 'Sign-up did not return a user. Try again.',
          ),
        );
      }
      final view = AuthSessionView(
        userId: user.id,
        email: user.email,
        emailConfirmed: user.emailConfirmedAt != null,
      );
      state = AsyncData(view);
      return Ok(view);
    } on AuthException catch (e) {
      return Err(
        AppError(
          kind: AppErrorKind.badRequest,
          code: 'signup_failed',
          message: e.message,
        ),
      );
    } catch (e) {
      return Err(AppError.network(e));
    }
  }

  Future<Result<void, AppError>> resetPassword({required String email}) async {
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .resetPasswordForEmail(email.trim());
      return const Ok(null);
    } on AuthException catch (e) {
      return Err(
        AppError(
          kind: AppErrorKind.badRequest,
          code: 'reset_failed',
          message: e.message,
        ),
      );
    } catch (e) {
      return Err(AppError.network(e));
    }
  }

  Future<void> signOut() async {
    await ref.read(supabaseClientProvider).auth.signOut();
    // Wipe local settings — they belong to the signed-out identity.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('posthog_opt_in');
    await prefs.remove('onboarding_consent_version');
    // The authStateChangesProvider listener will rebuild us.
  }
}
