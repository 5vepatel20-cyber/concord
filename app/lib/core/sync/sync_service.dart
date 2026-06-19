// Offline symptom-queue drain.
//
// Wakes when:
//   - connectivity_plus reports a non-none result (debounced 2s)
//   - auth state transitions to AuthSignedIn
//   - a new report is enqueued (manual trigger)
//
// Drains `local_symptom_reports` rows where `synced_at IS NULL` in oldest-first
// order, POSTs each to /api/symptoms/submit, and marks them synced on success
// or records the error on failure.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/symptom_repository.dart';
import '../../data/supabase/supabase_provider.dart';
import '../clock/clock.dart';
import '../storage/database_provider.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref);
});

class SyncService {
  SyncService(this._ref) {
    _wire();
  }

  final Ref _ref;
  Timer? _connectivityDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<AuthState>? _authSub;
  bool _draining = false;

  void _wire() {
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);
    _authSub =
        _ref.read(supabaseClientProvider).auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn) {
        unawaited(drain());
      }
    });
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!online) return;
    _connectivityDebounce?.cancel();
    _connectivityDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(drain());
    });
  }

  /// Drain the queue. Safe to call repeatedly — reentrancy guard via [_draining].
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final db = await _ref.read(appDatabaseProvider.future);
      final repo = _ref.read(symptomRepositoryProvider);
      final clock = _ref.read(clockProvider);

      while (true) {
        final pending = await db.pendingSymptomReports();
        if (pending.isEmpty) break;
        for (final report in pending) {
          try {
            final result = await repo.submitOnline(report.payloadJson);
            await db.markSymptomReportSynced(
              localId: report.localId,
              serverId: result.serverId,
              syncedAt: clock.nowUtc(),
            );
          } catch (e) {
            await db.markSymptomReportFailed(
              localId: report.localId,
              error: e.toString(),
            );
            // Stop draining on first failure — next trigger will retry.
            return;
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    _connectivityDebounce?.cancel();
    _connSub?.cancel();
    _authSub?.cancel();
  }
}