// Local sqlite database for the offline symptom queue + cached vocab.
//
// Hand-rolled (no codegen) to avoid an analyzer version conflict between
// drift_dev 2.28 and analyzer 7.6 that breaks build_runner on this toolchain.
//
// WAL mode is enabled on open to keep reads non-blocking during symptom
// submit writes (BRAND.md UX requirement: quick-log must feel instant).
//
// `local_symptom_reports`:
//   - local_id (UUID, client-generated) is the durable identity.
//   - server_id is populated after successful POST to /api/symptoms/submit.
//   - payload_json is the exact request body we sent (snapshot at submit time).
//   - synced_at is null until the server confirms.
//
// `cached_vocab`:
//   - Mirrors `condition` / `symptom_term` rows from Supabase for offline use.
//   - key + value pair: key is "<table>:<id>", value is the JSON row.

import 'package:drift/drift.dart';

import '../sync/sync_service.dart';
import 'database_connection.dart';

class PendingSymptomReport {
  const PendingSymptomReport({
    required this.localId,
    required this.payloadJson,
    required this.createdAt,
    this.syncError,
  });

  final String localId;
  final String payloadJson;
  final DateTime createdAt;
  final String? syncError;
}

/// Plain SQLite wrapper. Singleton — opening the same sqlite file twice on
/// iOS corrupts WAL.
class AppDatabase extends GeneratedDatabase implements DatabaseLike {
  AppDatabase._(super.e);

  /// We use raw SQL only; no codegen tables exist.
  @override
  Iterable<TableInfo> get allTables => const [];

  static AppDatabase? _instance;

  /// Open (or return) the app's sqlite database.
  static Future<AppDatabase> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final executor = openAppDatabase();
    final connection = DatabaseConnection(
      executor,
      closeStreamsSynchronously: false,
    );
    final created = AppDatabase._(connection);
    await created._onOpen();
    _instance = created;
    return created;
  }

  Future<void> _onOpen() async {
    // WAL must be set before any tables are created in this connection.
    await customStatement('PRAGMA journal_mode = WAL;');
    await customStatement('PRAGMA foreign_keys = ON;');
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await _createV1(m.database);
      await _createV2(m.database);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _createV2(m.database);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode = WAL;');
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );

  static Future<void> _createV1(DatabaseConnectionUser db) async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_symptom_reports (
        local_id TEXT PRIMARY KEY NOT NULL,
        server_id TEXT,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        sync_error TEXT
      );
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS cached_vocab (
        key TEXT PRIMARY KEY NOT NULL,
        value_json TEXT NOT NULL,
        fetched_at INTEGER NOT NULL
      );
    ''');
  }

  static Future<void> _createV2(DatabaseConnectionUser db) async {
    // MED-01..06: medication drafts queue (POST /api/medications) and
    // adherence drafts queue (POST /api/medications/:id/adherence).
    // Same offline-first pattern as local_symptom_reports: client UUID,
    // payload JSON, synced_at populated after server ack.
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_medication_drafts (
        local_id TEXT PRIMARY KEY NOT NULL,
        server_id TEXT,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        sync_error TEXT
      );
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_adherence_drafts (
        local_id TEXT PRIMARY KEY NOT NULL,
        server_id TEXT,
        medication_local_id TEXT,
        medication_server_id TEXT,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        sync_error TEXT
      );
    ''');
    // Mirror of server-confirmed meds so the UI can render a list
    // immediately on cold start without waiting for the network.
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS cached_medications (
        server_id TEXT PRIMARY KEY NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  // ── Symptom queue ───────────────────────────────────────────────────────────

  Future<void> enqueueSymptomReport({
    required String localId,
    required String payloadJson,
    required DateTime createdAt,
  }) {
    return customStatement(
      'INSERT OR REPLACE INTO local_symptom_reports '
      '(local_id, payload_json, created_at) VALUES (?, ?, ?)',
      [localId, payloadJson, createdAt.millisecondsSinceEpoch],
    );
  }

  @override
  Future<List<PendingSymptomReport>> pendingSymptomReports() async {
    final result = await customSelect(
      'SELECT local_id, payload_json, created_at, sync_error '
      'FROM local_symptom_reports WHERE synced_at IS NULL '
      'ORDER BY created_at ASC',
    ).get();
    return result
        .map(
          (r) => PendingSymptomReport(
            localId: r.read<String>('local_id'),
            payloadJson: r.read<String>('payload_json'),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r.read<int>('created_at'),
            ),
            syncError: r.readNullable<String>('sync_error'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markSymptomReportSynced({
    required String localId,
    required String serverId,
    required DateTime syncedAt,
  }) {
    return customStatement(
      'UPDATE local_symptom_reports SET server_id = ?, synced_at = ?, '
      'sync_error = NULL WHERE local_id = ?',
      [serverId, syncedAt.millisecondsSinceEpoch, localId],
    );
  }

  @override
  Future<void> markSymptomReportFailed({
    required String localId,
    required String error,
  }) {
    return customStatement(
      'UPDATE local_symptom_reports SET sync_error = ? WHERE local_id = ?',
      [error, localId],
    );
  }

  // ── Vocab cache ─────────────────────────────────────────────────────────────

  Future<String?> cachedVocab(String key) async {
    final row = await customSelect(
      'SELECT value_json FROM cached_vocab WHERE key = ?',
      variables: [Variable.withString(key)],
    ).getSingleOrNull();
    return row?.read<String>('value_json');
  }

  Future<void> putCachedVocab({
    required String key,
    required String valueJson,
    required DateTime fetchedAt,
  }) {
    return customStatement(
      'INSERT OR REPLACE INTO cached_vocab (key, value_json, fetched_at) '
      'VALUES (?, ?, ?)',
      [key, valueJson, fetchedAt.millisecondsSinceEpoch],
    );
  }

  // ── Medication drafts (MED-01..06) ─────────────────────────────────────────

  Future<void> enqueueMedicationDraft({
    required String localId,
    required String payloadJson,
    required DateTime createdAt,
  }) {
    return customStatement(
      'INSERT OR REPLACE INTO local_medication_drafts '
      '(local_id, payload_json, created_at) VALUES (?, ?, ?)',
      [localId, payloadJson, createdAt.millisecondsSinceEpoch],
    );
  }

  @override
  Future<List<PendingSymptomReport>> pendingMedicationDrafts() async {
    final result = await customSelect(
      'SELECT local_id, payload_json, created_at, sync_error '
      'FROM local_medication_drafts WHERE synced_at IS NULL '
      'ORDER BY created_at ASC',
    ).get();
    return result
        .map(
          (r) => PendingSymptomReport(
            localId: r.read<String>('local_id'),
            payloadJson: r.read<String>('payload_json'),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r.read<int>('created_at'),
            ),
            syncError: r.readNullable<String>('sync_error'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markMedicationDraftSynced({
    required String localId,
    required String serverId,
    required String payloadJson,
    required DateTime syncedAt,
  }) async {
    await customStatement(
      'UPDATE local_medication_drafts SET server_id = ?, synced_at = ?, '
      'sync_error = NULL WHERE local_id = ?',
      [serverId, syncedAt.millisecondsSinceEpoch, localId],
    );
    // Refresh the cache so the medications list shows this row on next read.
    await customStatement(
      'INSERT OR REPLACE INTO cached_medications '
      '(server_id, payload_json, updated_at) VALUES (?, ?, ?)',
      [serverId, payloadJson, syncedAt.millisecondsSinceEpoch],
    );
  }

  @override
  Future<void> markMedicationDraftFailed({
    required String localId,
    required String error,
  }) {
    return customStatement(
      'UPDATE local_medication_drafts SET sync_error = ? WHERE local_id = ?',
      [error],
    );
  }

  Future<List<CachedMedication>> cachedMedications() async {
    final result = await customSelect(
      'SELECT server_id, payload_json, updated_at FROM cached_medications '
      'ORDER BY updated_at DESC',
    ).get();
    return result
        .map(
          (r) => CachedMedication(
            serverId: r.read<String>('server_id'),
            payloadJson: r.read<String>('payload_json'),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              r.read<int>('updated_at'),
            ),
          ),
        )
        .toList(growable: false);
  }

  // ── Adherence drafts ────────────────────────────────────────────────────────

  Future<void> enqueueAdherenceDraft({
    required String localId,
    required String payloadJson,
    required String? medicationLocalId,
    required String? medicationServerId,
    required DateTime createdAt,
  }) {
    return customStatement(
      'INSERT OR REPLACE INTO local_adherence_drafts '
      '(local_id, payload_json, medication_local_id, medication_server_id, '
      'created_at) VALUES (?, ?, ?, ?, ?)',
      [
        localId,
        payloadJson,
        medicationLocalId,
        medicationServerId,
        createdAt.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<List<PendingAdherenceDraft>> pendingAdherenceDrafts() async {
    final result = await customSelect(
      'SELECT local_id, payload_json, medication_local_id, '
      'medication_server_id, created_at, sync_error '
      'FROM local_adherence_drafts WHERE synced_at IS NULL '
      'ORDER BY created_at ASC',
    ).get();
    return result
        .map(
          (r) => PendingAdherenceDraft(
            localId: r.read<String>('local_id'),
            payloadJson: r.read<String>('payload_json'),
            medicationLocalId: r.readNullable<String>('medication_local_id'),
            medicationServerId: r.readNullable<String>('medication_server_id'),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r.read<int>('created_at'),
            ),
            syncError: r.readNullable<String>('sync_error'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markAdherenceDraftSynced({
    required String localId,
    required String serverId,
    required DateTime syncedAt,
  }) {
    return customStatement(
      'UPDATE local_adherence_drafts SET server_id = ?, synced_at = ?, '
      'sync_error = NULL WHERE local_id = ?',
      [serverId, syncedAt.millisecondsSinceEpoch, localId],
    );
  }

  @override
  Future<void> markAdherenceDraftFailed({
    required String localId,
    required String error,
  }) {
    return customStatement(
      'UPDATE local_adherence_drafts SET sync_error = ? WHERE local_id = ?',
      [error],
    );
  }
}

/// A server-confirmed medication that was cached locally for instant
/// render on cold start.
class CachedMedication {
  const CachedMedication({
    required this.serverId,
    required this.payloadJson,
    required this.updatedAt,
  });
  final String serverId;
  final String payloadJson;
  final DateTime updatedAt;
}

/// A row in `local_adherence_drafts` waiting to be POSTed to
/// `/api/medications/:id/adherence`.
class PendingAdherenceDraft {
  const PendingAdherenceDraft({
    required this.localId,
    required this.payloadJson,
    required this.medicationLocalId,
    required this.medicationServerId,
    required this.createdAt,
    this.syncError,
  });

  final String localId;
  final String payloadJson;

  /// The localId of the medication this event is for. May be null if
  /// the medication was already synced (then [medicationServerId] is set).
  final String? medicationLocalId;

  /// The serverId of the medication this event is for, when known.
  /// When the medication itself is still in the offline queue, this is
  /// null and the adherence event must wait.
  final String? medicationServerId;

  final DateTime createdAt;
  final String? syncError;
}
