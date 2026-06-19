// Symptom report repository — offline-first submission.
//
// `submit()` writes to drift FIRST and returns immediately with a localId.
// The sync_service picks up the row when connectivity + auth permit and POSTs
// to /api/symptoms/submit.
//
// `submitOnline(payloadJson)` is the network call itself, used by the sync
// drain. It is exposed separately so tests can stub it without touching the
// database.

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
import '../supabase/supabase_provider.dart';

final symptomRepositoryProvider = Provider<SymptomRepository>((ref) {
  return SymptomRepository(ref);
});

class SymptomReportInput {
  const SymptomReportInput({
    required this.responses,
    required this.occurredAt,
    required this.source,
    this.recallWindow = RecallWindow.now,
    this.notes,
  });

  /// Map keyed by symptom_term_id; value is the chosen severity grade (0..3).
  /// Using a Map rather than a List to preserve order of choice + allow
  /// easy dedup at the boundary.
  final Map<String, int> responses;

  /// UTC timestamp of when the symptom occurred (may be in the past).
  final DateTime occurredAt;

  /// 'self' or 'caregiver' (voice deferred to 1.1).
  final String source;

  /// Whether the patient is logging what they feel right now, or recalling
  /// the past week. Mirrors the backend's `recall_window` enum.
  final RecallWindow recallWindow;

  /// Optional free-text narrative. Backend constraint: 4000 chars max.
  final String? notes;
}

enum RecallWindow { now, past7Days }

class SymptomSubmitReceipt {
  const SymptomSubmitReceipt({
    required this.localId,
    this.serverId,
    this.emergencyGuidance,
  });
  final String localId;
  final String? serverId;

  /// Populated when the server returns EMERGENCY_GUIDANCE (a grade-3 response
  /// is paired with what to do right now). Null for non-severe or for offline
  /// submissions that haven't synced yet.
  final String? emergencyGuidance;
}

class SymptomRepository {
  SymptomRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  /// Offline-first. Tries an immediate online submit so the caller can show
  /// emergency guidance for severe (grade-3) reports without waiting for the
  /// sync drain. On any failure (offline, timeout, server error) it falls
  /// back to enqueueing in drift and the sync_service catches up later.
  Future<Result<SymptomSubmitReceipt, AppError>> submit(
    SymptomReportInput input,
  ) async {
    try {
      final db = await _ref.read(appDatabaseProvider.future);
      final clock = _ref.read(clockProvider);

      final localId = _uuid.v4();
      final payload = jsonEncode({
        'local_id': localId,
        'occurred_at': input.occurredAt.toUtc().toIso8601String(),
        'source': input.source,
        'recall_window': input.recallWindow == RecallWindow.past7Days
            ? 'past_7_days'
            : 'now',
        'notes': input.notes,
        'responses': input.responses,
      });

      await db.enqueueSymptomReport(
        localId: localId,
        payloadJson: payload,
        createdAt: clock.nowUtc(),
      );

      // Best-effort immediate online submit. Short timeout so a flaky network
      // doesn't keep the UI blocked; failure here just means we wait for the
      // sync drain.
      try {
        final result = await submitOnline(payload)
            .timeout(const Duration(seconds: 5));
        await db.markSymptomReportSynced(
          localId: localId,
          serverId: result.serverId,
          syncedAt: clock.nowUtc(),
        );
        return Ok(SymptomSubmitReceipt(
          localId: localId,
          serverId: result.serverId,
          emergencyGuidance: result.emergencyGuidance,
        ));
      } catch (_) {
        // Network/timeout/server error — fall through to the sync drain.
        // ignore: discarded_futures
        _ref.read(syncServiceProvider).drain();
        return Ok(SymptomSubmitReceipt(localId: localId));
      }
    } catch (e) {
      return Err(AppError(
        kind: AppErrorKind.database,
        code: 'enqueue_failed',
        message: 'Could not save symptom locally',
        cause: e,
      ));
    }
  }

  /// Result of a network submit. Exposes emergency guidance (if any) alongside
  /// the server-assigned id so the UI can show it without an extra fetch.
  Future<SubmitOnlineResult> submitOnline(String payloadJson) async {
    final apiBase = _ref.read(apiBaseUrlProvider);
    // Read live from the client so a refreshed JWT is used.
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      throw StateError('Cannot sync symptoms without an auth session');
    }
    final token = session.accessToken;
    final uri = Uri.parse('$apiBase/api/symptoms/submit');

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: payloadJson,
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'submitOnline failed: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    // Backend contract: { ok: true, report_id: "...", emergency_guidance: ... }
    final reportId = body['report_id'] as String?;
    if (reportId == null) {
      throw const FormatException('submitOnline response missing report_id');
    }
    final guidance = body['emergency_guidance']?.toString();
    return SubmitOnlineResult(
      serverId: reportId,
      emergencyGuidance: (guidance == null || guidance.isEmpty) ? null : guidance,
    );
  }
}

class SubmitOnlineResult {
  const SubmitOnlineResult({required this.serverId, this.emergencyGuidance});
  final String serverId;
  final String? emergencyGuidance;
}