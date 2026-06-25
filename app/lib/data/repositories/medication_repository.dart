// MedicationRepository — offline-first medications + adherence (MED-01..06).
//
// Same shape as SymptomRepository: write to drift first, return a
// client-generated UUID; the sync drain POSTs to the backend with that UUID
// as the Idempotency-Key.
//
// Reads are NOT cached locally in v1 — the medications list is fetched
// from the server when the screen mounts. The cache table is populated as
// a side-effect of successful creates, so cold start shows prior meds
// while the network call is in flight.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/clock/clock.dart';
import '../../core/result/result.dart';
import '../../core/storage/database_provider.dart';
import '../../core/sync/sync_service.dart';
import '../models/medication.dart';
import '../supabase/supabase_provider.dart';

final medicationRepositoryProvider = Provider<MedicationRepository>((ref) {
  return MedicationRepository(ref);
});

class MedicationDraftReceipt {
  const MedicationDraftReceipt({required this.localId, this.serverId});
  final String localId;
  final String? serverId;
}

class AdherenceDraftReceipt {
  const AdherenceDraftReceipt({required this.localId, this.serverId});
  final String localId;
  final String? serverId;
}

class MedicationRepository {
  MedicationRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  /// Fetch the current list of medications from the server. Used by the
  /// medications screen on mount. Network-only; falls back to local cache
  /// if the network call fails.
  Future<Result<List<Medication>, AppError>> fetchAll({
    bool onlyActive = true,
  }) async {
    try {
      final apiBase = _ref.read(apiBaseUrlProvider);
      final session = _ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) {
        return const Err(
          AppError(
            kind: AppErrorKind.unauthorized,
            code: 'no_session',
            message: 'Not signed in',
          ),
        );
      }
      final uri = Uri.parse(
        '$apiBase/api/medications'
        '?active=${onlyActive ? 'true' : 'false'}',
      );
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer ${session.accessToken}'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'fetchAll failed: ${response.statusCode} ${response.body}',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final meds = (body['medications'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Medication.fromJson)
          .toList();
      // Refresh cache for next cold start.
      final db = await _ref.read(appDatabaseProvider.future);
      final clock = _ref.read(clockProvider);
      for (final m in meds) {
        if (m.id == null) continue;
        await db.customStatement(
          'INSERT OR REPLACE INTO cached_medications '
          '(server_id, payload_json, updated_at) VALUES (?, ?, ?)',
          [m.id, jsonEncode(m.toJson()), clock.nowUtc().millisecondsSinceEpoch],
        );
      }
      return Ok(meds);
    } catch (e) {
      // Fall back to local cache.
      try {
        final db = await _ref.read(appDatabaseProvider.future);
        final cached = await db.cachedMedications();
        final meds = cached
            .map(
              (c) => Medication.fromJson(
                jsonDecode(c.payloadJson) as Map<String, dynamic>,
              ),
            )
            .where((m) => onlyActive ? m.active : true)
            .toList();
        if (meds.isNotEmpty) {
          return Ok(meds);
        }
      } catch (_) {
        // fall through to the error
      }
      return Err(
        AppError(
          kind: AppErrorKind.network,
          code: 'fetch_failed',
          message: 'Could not load medications',
          cause: e,
        ),
      );
    }
  }

  /// Read the locally-cached medications (no network). Returns the empty
  /// list if nothing is cached. Useful for instant render on cold start.
  Future<List<Medication>> cachedMeds() async {
    try {
      final db = await _ref.read(appDatabaseProvider.future);
      final cached = await db.cachedMedications();
      return cached
          .map(
            (c) => Medication.fromJson(
              jsonDecode(c.payloadJson) as Map<String, dynamic>,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Offline-first create. Writes the draft to drift, returns the localId
  /// immediately, and best-effort POSTs to /api/medications. The sync
  /// drain catches up on retry with the Idempotency-Key header.
  Future<Result<MedicationDraftReceipt, AppError>> create(
    Medication draft,
  ) async {
    try {
      final db = await _ref.read(appDatabaseProvider.future);
      final clock = _ref.read(clockProvider);

      final localId = _uuid.v4();
      final payload = encodeMedicationCreate(draft);

      await db.enqueueMedicationDraft(
        localId: localId,
        payloadJson: payload,
        createdAt: clock.nowUtc(),
      );

      try {
        final created = await createOnline(
          payload,
          idempotencyKey: localId,
        ).timeout(const Duration(seconds: 8));
        final serverId = created.id;
        if (serverId != null) {
          await db.markMedicationDraftSynced(
            localId: localId,
            serverId: serverId,
            payloadJson: jsonEncode(created.toJson()),
            syncedAt: clock.nowUtc(),
          );
        }
        return Ok(MedicationDraftReceipt(localId: localId, serverId: serverId));
      } catch (_) {
        // Network/server error — fall through to the sync drain.
        // ignore: discarded_futures
        _ref.read(syncServiceProvider).drain();
        return Ok(MedicationDraftReceipt(localId: localId));
      }
    } catch (e) {
      return Err(
        AppError(
          kind: AppErrorKind.database,
          code: 'enqueue_failed',
          message: 'Could not save medication locally',
          cause: e,
        ),
      );
    }
  }

  /// POST /api/medications. [idempotencyKey] is the row's localId.
  Future<Medication> createOnline(
    String payloadJson, {
    required String idempotencyKey,
  }) async {
    final apiBase = _ref.read(apiBaseUrlProvider);
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      throw StateError('Cannot sync medications without an auth session');
    }
    final uri = Uri.parse('$apiBase/api/medications');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
            'Idempotency-Key': idempotencyKey,
          },
          body: payloadJson,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'createOnline failed: ${response.statusCode} ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final m = body['medication'] as Map<String, dynamic>?;
    if (m == null) {
      throw const FormatException('createOnline response missing medication');
    }
    return Medication.fromJson(m);
  }

  /// Log an adherence event. Offline-first: writes to drift, returns the
  /// localId immediately, sync drain POSTs later.
  ///
  /// [medicationServerId] is the server id when known; [medicationLocalId]
  /// is the local-only id when the parent medication is itself still in
  /// the offline queue. The sync drain waits for the medication to be
  /// confirmed before posting the adherence event.
  Future<Result<AdherenceDraftReceipt, AppError>> logAdherence({
    required String medicationServerId,
    String? medicationLocalId,
    required AdherenceEvent event,
  }) async {
    try {
      final db = await _ref.read(appDatabaseProvider.future);
      final clock = _ref.read(clockProvider);

      final localId = _uuid.v4();
      final payload = encodeAdherence(event);

      await db.enqueueAdherenceDraft(
        localId: localId,
        payloadJson: payload,
        medicationLocalId: medicationLocalId,
        medicationServerId: medicationServerId,
        createdAt: clock.nowUtc(),
      );

      try {
        final serverEvent = await logAdherenceOnline(
          medicationServerId: medicationServerId,
          payloadJson: payload,
          idempotencyKey: localId,
        ).timeout(const Duration(seconds: 8));
        await db.markAdherenceDraftSynced(
          localId: localId,
          serverId: serverEvent.id,
          syncedAt: clock.nowUtc(),
        );
        return Ok(
          AdherenceDraftReceipt(localId: localId, serverId: serverEvent.id),
        );
      } catch (_) {
        // ignore: discarded_futures
        _ref.read(syncServiceProvider).drain();
        return Ok(AdherenceDraftReceipt(localId: localId));
      }
    } catch (e) {
      return Err(
        AppError(
          kind: AppErrorKind.database,
          code: 'enqueue_failed',
          message: 'Could not save adherence event locally',
          cause: e,
        ),
      );
    }
  }

  /// POST /api/medications/:id/adherence. Returns the persisted event id.
  Future<AdherenceId> logAdherenceOnline({
    required String medicationServerId,
    required String payloadJson,
    required String idempotencyKey,
  }) async {
    final apiBase = _ref.read(apiBaseUrlProvider);
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      throw StateError('Cannot sync adherence without an auth session');
    }
    final uri = Uri.parse(
      '$apiBase/api/medications/$medicationServerId/adherence',
    );
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
            'Idempotency-Key': idempotencyKey,
          },
          body: payloadJson,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'logAdherenceOnline failed: ${response.statusCode} ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final ev = body['event'] as Map<String, dynamic>?;
    if (ev == null || ev['id'] == null) {
      throw const FormatException(
        'logAdherenceOnline response missing event.id',
      );
    }
    return AdherenceId(id: ev['id'] as String);
  }
}

/// Deactivate a medication server-side (PATCH /api/medications/:id).
/// Returns the updated Medication on success.
Future<Result<Medication, AppError>> deactivate(String medicationId) async {
  try {
    final apiBase = _ref.read(apiBaseUrlProvider);
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      return const Err(
        AppError(
          kind: AppErrorKind.unauthorized,
          code: 'no_session',
          message: 'Not signed in',
        ),
      );
    }
    final uri = Uri.parse('$apiBase/api/medications/$medicationId');
    final response = await http
        .patch(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode({'active': false}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'deactivate failed: ${response.statusCode} ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final med = body['medication'] as Map<String, dynamic>?;
    if (med == null) {
      throw const FormatException('deactivate response missing medication');
    }
    return Ok(Medication.fromJson(med));
  } catch (e) {
    return Err(
      AppError(
        kind: AppErrorKind.network,
        code: 'deactivate_failed',
        message: 'Could not deactivate medication',
        cause: e,
      ),
    );
  }
}

/// Server-assigned id of a persisted adherence event.
class AdherenceId {
  const AdherenceId({required this.id});
  final String id;
}
