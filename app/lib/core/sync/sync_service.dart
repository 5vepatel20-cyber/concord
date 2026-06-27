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
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/medication_repository.dart';
import '../../data/repositories/symptom_repository.dart';
import '../../data/supabase/supabase_provider.dart';
import '../clock/clock.dart';
import '../storage/database.dart';
import '../storage/database_provider.dart';

/// Subset of AppDatabase the sync drain touches. Lets us write the drain
/// methods as pure functions against an interface for easier testing.
abstract class DatabaseLike {
  Future<List<PendingSymptomReport>> pendingSymptomReports();
  Future<void> markSymptomReportSynced({
    required String localId,
    required String serverId,
    required DateTime syncedAt,
  });
  Future<void> markSymptomReportFailed({
    required String localId,
    required String error,
  });
  Future<List<PendingSymptomReport>> pendingMedicationDrafts();
  Future<void> markMedicationDraftSynced({
    required String localId,
    required String serverId,
    required String payloadJson,
    required DateTime syncedAt,
  });
  Future<void> markMedicationDraftFailed({
    required String localId,
    required String error,
  });
  Future<List<PendingAdherenceDraft>> pendingAdherenceDrafts();
  Future<void> markAdherenceDraftSynced({
    required String localId,
    required String serverId,
    required DateTime syncedAt,
  });
  Future<void> markAdherenceDraftFailed({
    required String localId,
    required String error,
  });
}

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
    _connSub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    _authSub = _ref.read(supabaseClientProvider).auth.onAuthStateChange.listen((
      event,
    ) {
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
      final symptomRepo = _ref.read(symptomRepositoryProvider);
      final medRepo = _ref.read(medicationRepositoryProvider);
      final clock = _ref.read(clockProvider);

      // 1) Symptom reports.
      await _drainSymptomReports(db, symptomRepo, clock);

      // 2) Medication drafts. These must drain BEFORE adherence drafts
      //    since adherence rows reference medication server ids that are
      //    only populated once the medication POST succeeds.
      await _drainMedicationDrafts(db, medRepo, clock);

      // 3) Adherence events. Skip rows whose medication is still offline.
      await _drainAdherenceDrafts(db, medRepo, clock);
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainSymptomReports(
    DatabaseLike db,
    SymptomRepository repo,
    Clock clock,
  ) async {
    while (true) {
      final pending = await db.pendingSymptomReports();
      if (pending.isEmpty) break;
      for (final report in pending) {
        try {
          final result = await repo.submitOnline(
            report.payloadJson,
            idempotencyKey: report.localId,
          );
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
          return; // stop on first failure; next trigger retries
        }
      }
    }
  }

  Future<void> _drainMedicationDrafts(
    DatabaseLike db,
    MedicationRepository repo,
    Clock clock,
  ) async {
    while (true) {
      final pending = await db.pendingMedicationDrafts();
      if (pending.isEmpty) break;
      for (final draft in pending) {
        try {
          final created = await repo.createOnline(
            draft.payloadJson,
            idempotencyKey: draft.localId,
          );
          await db.markMedicationDraftSynced(
            localId: draft.localId,
            serverId: created.id ?? '',
            payloadJson: jsonEncode(created.toJson()),
            syncedAt: clock.nowUtc(),
          );
        } catch (e) {
          await db.markMedicationDraftFailed(
            localId: draft.localId,
            error: e.toString(),
          );
          return;
        }
      }
    }
  }

  Future<void> _drainAdherenceDrafts(
    DatabaseLike db,
    MedicationRepository repo,
    Clock clock,
  ) async {
    while (true) {
      final pending = await db.pendingAdherenceDrafts();
      if (pending.isEmpty) break;
      for (final draft in pending) {
        // If the parent medication is itself still in the offline queue,
        // we cannot POST the adherence event yet — it would 404 on the
        // server. Skip until the medication is confirmed.
        if (draft.medicationServerId == null) continue;
        try {
          final ack = await repo.logAdherenceOnline(
            medicationServerId: draft.medicationServerId!,
            payloadJson: draft.payloadJson,
            idempotencyKey: draft.localId,
          );
          await db.markAdherenceDraftSynced(
            localId: draft.localId,
            serverId: ack.id,
            syncedAt: clock.nowUtc(),
          );
        } catch (e) {
          await db.markAdherenceDraftFailed(
            localId: draft.localId,
            error: e.toString(),
          );
          return;
        }
      }
      // If we hit the "skip" path repeatedly, we'd loop forever; cap at
      // one pass and let the next trigger handle it once the medication
      // queue drains.
      break;
    }
  }

  void dispose() {
    _connectivityDebounce?.cancel();
    _connSub?.cancel();
    _authSub?.cancel();
  }
}
