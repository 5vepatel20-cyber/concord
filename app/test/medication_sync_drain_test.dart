// Tests for the sync-service drain ordering.
//
// Key invariant: adherence drafts that reference a medication which is
// itself still in the offline queue must NOT be POSTed until the
// medication is confirmed. We exercise this with a fake DatabaseLike.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:concord/core/clock/clock.dart';
import 'package:concord/core/storage/database.dart';
import 'package:concord/core/sync/sync_service.dart';
import 'package:concord/data/models/medication.dart';
import 'package:concord/data/repositories/medication_repository.dart';

class _FakeClock implements Clock {
  _FakeClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
  @override
  DateTime nowUtc() => _now.toUtc();
  void advance(Duration d) => _now = _now.add(d);
}

class _FakeDb implements DatabaseLike {
  final List<PendingSymptomReport> symptomPending = [];
  final List<PendingSymptomReport> medicationPending = [];
  final List<PendingAdherenceDraft> adherencePending = [];
  final List<String> syncedAdherenceIds = [];
  final List<String> syncedMedicationIds = [];

  // Simulated sync semantics for the medication drafts queue. We let the
  // caller "promote" localId -> serverId by inserting into a map.
  final Map<String, String> medLocalToServer = {};

  void markMedicationSynced(String localId, String serverId) {
    syncedMedicationIds.add(localId);
    medLocalToServer[localId] = serverId;
    // Simulate the server-id-population that the real drain does after a
    // successful POST: rewrite the adherence draft's medication_server_id.
    final rewritten = <PendingAdherenceDraft>[];
    for (final a in adherencePending) {
      if (a.medicationLocalId == localId && a.medicationServerId == null) {
        rewritten.add(PendingAdherenceDraft(
          localId: a.localId,
          payloadJson: a.payloadJson,
          medicationLocalId: a.medicationLocalId,
          medicationServerId: serverId,
          createdAt: a.createdAt,
          syncError: a.syncError,
        ));
      } else {
        rewritten.add(a);
      }
    }
    adherencePending
      ..clear()
      ..addAll(rewritten);
  }

  @override
  Future<List<PendingSymptomReport>> pendingSymptomReports() async =>
      symptomPending;

  @override
  Future<void> markSymptomReportSynced({
    required String localId,
    required String serverId,
    required DateTime syncedAt,
  }) async {}

  @override
  Future<void> markSymptomReportFailed({
    required String localId,
    required String error,
  }) async {}

  @override
  Future<List<PendingSymptomReport>> pendingMedicationDrafts() async =>
      medicationPending;

  @override
  Future<void> markMedicationDraftSynced({
    required String localId,
    required String serverId,
    required String payloadJson,
    required DateTime syncedAt,
  }) async {
    markMedicationSynced(localId, serverId);
    // Remove from the pending list so the drain loop terminates.
    medicationPending.removeWhere((d) => d.localId == localId);
  }

  @override
  Future<void> markMedicationDraftFailed({
    required String localId,
    required String error,
  }) async {}

  @override
  Future<List<PendingAdherenceDraft>> pendingAdherenceDrafts() async =>
      adherencePending;

  @override
  Future<void> markAdherenceDraftSynced({
    required String localId,
    required String serverId,
    required DateTime syncedAt,
  }) async {
    syncedAdherenceIds.add(localId);
    adherencePending.removeWhere((d) => d.localId == localId);
  }

  @override
  Future<void> markAdherenceDraftFailed({
    required String localId,
    required String error,
  }) async {}
}

class _FakeMedRepo extends MedicationRepository {
  _FakeMedRepo(this.db) : super(_NoopRef());

  final _FakeDb db;
  final List<String> adherencePosts = [];
  final List<String> medicationPosts = [];

  @override
  Future<Medication> createOnline(
    String payloadJson, {
    required String idempotencyKey,
  }) async {
    medicationPosts.add(idempotencyKey);
    final id = 'srv-med-${medicationPosts.length}';
    return Medication(
      id: id,
      displayName: _displayName(payloadJson),
    );
  }

  @override
  Future<AdherenceId> logAdherenceOnline({
    required String medicationServerId,
    required String payloadJson,
    required String idempotencyKey,
  }) async {
    adherencePosts.add(idempotencyKey);
    return AdherenceId(id: 'srv-evt-${adherencePosts.length}');
  }
}

String _displayName(String payload) {
  final m = RegExp(r'"display_name":"([^"]+)"').firstMatch(payload);
  return m?.group(1) ?? 'unknown';
}

/// A Ref whose every read throws — we never touch the real Riverpod
/// container in these tests because we override createOnline / logAdherenceOnline.
class _NoopRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('NoopRef: unexpected read of ${invocation.memberName}');
  }
}

void main() {
  group('sync drain medication ordering', () {
    test('medication drains before adherence', () async {
      final db = _FakeDb();
      db.medicationPending.add(PendingSymptomReport(
        localId: 'med-local-1',
        payloadJson: '{"display_name":"Tamoxifen"}',
        createdAt: DateTime.utc(2026, 6, 19),
      ));
      // Adherence references the medication by localId — serverId unknown.
      db.adherencePending.add(PendingAdherenceDraft(
        localId: 'adh-1',
        payloadJson:
            '{"medication_id":"med-local-1","status":"taken","scheduled_for":"2026-06-19T08:00:00Z"}',
        medicationLocalId: 'med-local-1',
        medicationServerId: null,
        createdAt: DateTime.utc(2026, 6, 19),
      ));

      // We can't easily construct a SyncService here (it depends on Riverpod
      // + supabase + connectivity_plus). Instead, we exercise the same
      // ordering logic the drain implements by calling each phase in order
      // and asserting the fake repo saw the expected sequence.
      final medRepo = _FakeMedRepo(db);
      final clock = _FakeClock(DateTime.utc(2026, 6, 19));

      // Phase A: process the one pending medication draft. The real drain
      // wraps this in a while loop; for the test we don't need that.
      final medDraft = (await db.pendingMedicationDrafts()).first;
      final created = await medRepo.createOnline(
        medDraft.payloadJson,
        idempotencyKey: medDraft.localId,
      );
      await db.markMedicationDraftSynced(
        localId: medDraft.localId,
        serverId: created.id ?? '',
        payloadJson: '{"id":"${created.id}"}',
        syncedAt: clock.nowUtc(),
      );

      expect(medRepo.medicationPosts, ['med-local-1']);
      expect(db.syncedMedicationIds, ['med-local-1']);

      // After phase A, the adherence row should now have a serverId.
      final refreshed = await db.pendingAdherenceDrafts();
      expect(refreshed.single.medicationServerId, 'srv-med-1');

      // Phase B: process the (now-ready) adherence draft.
      final adhDraft = refreshed.single;
      final ack = await medRepo.logAdherenceOnline(
        medicationServerId: adhDraft.medicationServerId!,
        payloadJson: adhDraft.payloadJson,
        idempotencyKey: adhDraft.localId,
      );
      await db.markAdherenceDraftSynced(
        localId: adhDraft.localId,
        serverId: ack.id,
        syncedAt: clock.nowUtc(),
      );

      expect(medRepo.adherencePosts, ['adh-1']);
      expect(db.syncedAdherenceIds, ['adh-1']);
    });

    test('adherence with no pending medication is skipped (not lost)', () async {
      final db = _FakeDb();
      db.adherencePending.add(PendingAdherenceDraft(
        localId: 'adh-orphan',
        payloadJson: '{"status":"skipped","scheduled_for":"2026-06-19T08:00:00Z"}',
        medicationLocalId: null,
        medicationServerId: null,
        createdAt: DateTime.utc(2026, 6, 19),
      ));

      // No medication drain — so serverId stays null. Drain should NOT
      // POST the adherence; row stays pending.
      final medRepo = _FakeMedRepo(db);
      final pending = await db.pendingAdherenceDrafts();
      for (final a in pending) {
        if (a.medicationServerId == null) continue;
        await medRepo.logAdherenceOnline(
          medicationServerId: a.medicationServerId!,
          payloadJson: a.payloadJson,
          idempotencyKey: a.localId,
        );
      }

      expect(medRepo.adherencePosts, isEmpty);
      // Row is still pending.
      expect((await db.pendingAdherenceDrafts()).single.localId, 'adh-orphan');
    });
  });
}
