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

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
class AppDatabase extends GeneratedDatabase {
  AppDatabase._(super.e);

  /// We use raw SQL only; no codegen tables exist.
  @override
  Iterable<TableInfo> get allTables => const [];

  static AppDatabase? _instance;

  /// Open (or return) the app's sqlite database.
  static Future<AppDatabase> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final file = await _dbFile();
    final connection = DatabaseConnection(
      NativeDatabase.createInBackground(file),
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.database.customStatement('''
            CREATE TABLE IF NOT EXISTS local_symptom_reports (
              local_id TEXT PRIMARY KEY NOT NULL,
              server_id TEXT,
              payload_json TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              synced_at INTEGER,
              sync_error TEXT
            );
          ''');
          await m.database.customStatement('''
            CREATE TABLE IF NOT EXISTS cached_vocab (
              key TEXT PRIMARY KEY NOT NULL,
              value_json TEXT NOT NULL,
              fetched_at INTEGER NOT NULL
            );
          ''');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA journal_mode = WAL;');
          await customStatement('PRAGMA foreign_keys = ON;');
        },
      );

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

  Future<List<PendingSymptomReport>> pendingSymptomReports() async {
    final result = await customSelect(
      'SELECT local_id, payload_json, created_at, sync_error '
      'FROM local_symptom_reports WHERE synced_at IS NULL '
      'ORDER BY created_at ASC',
    ).get();
    return result
        .map((r) => PendingSymptomReport(
              localId: r.read<String>('local_id'),
              payloadJson: r.read<String>('payload_json'),
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                r.read<int>('created_at'),
              ),
              syncError: r.readNullable<String>('sync_error'),
            ))
        .toList(growable: false);
  }

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
}

Future<File> _dbFile() async {
  final folder = await getApplicationDocumentsDirectory();
  return File(p.join(folder.path, 'concord.sqlite'));
}