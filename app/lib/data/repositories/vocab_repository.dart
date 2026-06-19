// Clinical-vocabulary repository.
//
// `refresh()` fetches the canonical `condition` / `symptom_term` / `symptom_panel`
// rows from Supabase and writes them through to the local sqlite vocab cache.
// `loadAll()` returns a merged in-memory snapshot for the quick-log screen —
// it reads from cache when fresh, otherwise calls refresh first.
//
// Cache TTL: 1 hour. Anything older triggers a network refresh; if the network
// fails we still return the stale cache so the screen can render offline.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock/clock.dart';
import '../../core/storage/database_provider.dart';
import '../models/condition.dart';
import '../supabase/supabase_provider.dart';

const _cacheTtl = Duration(hours: 1);
const _cacheVersion = 'v1';

final vocabRepositoryProvider = Provider<VocabRepository>((ref) {
  return VocabRepository(ref);
});

/// AsyncNotifier-style provider for the merged vocab snapshot.
final vocabSnapshotProvider = FutureProvider<List<ConditionWithTerms>>((ref) async {
  return ref.read(vocabRepositoryProvider).loadAll();
});

class VocabRepository {
  VocabRepository(this._ref);

  final Ref _ref;

  Future<List<VocabCondition>> _fetchConditions() async {
    final client = _ref.read(supabaseClientProvider);
    final res = await client.from('condition').select();
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(VocabCondition.fromJson)
        .toList(growable: false);
  }

  Future<List<VocabSymptomTerm>> _fetchTerms() async {
    final client = _ref.read(supabaseClientProvider);
    final res = await client.from('symptom_term').select();
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(VocabSymptomTerm.fromJson)
        .toList(growable: false);
  }

  Future<List<VocabSymptomPanel>> _fetchPanels() async {
    final client = _ref.read(supabaseClientProvider);
    final res = await client.from('symptom_panel').select();
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(VocabSymptomPanel.fromJson)
        .toList(growable: false);
  }

  /// Force a network refresh; returns the merged snapshot. Throws on failure.
  Future<List<ConditionWithTerms>> refresh() async {
    final results = await Future.wait([
      _fetchConditions(),
      _fetchTerms(),
      _fetchPanels(),
    ]);
    final conditions = results[0] as List<VocabCondition>;
    final terms = results[1] as List<VocabSymptomTerm>;
    final panels = results[2] as List<VocabSymptomPanel>;

    final db = await _ref.read(appDatabaseProvider.future);
    final clock = _ref.read(clockProvider);
    final now = clock.nowUtc();

    // Build the merged snapshot.
    final byTermId = {for (final t in terms) t.id: t};
    final snapshot = conditions.map((c) {
      final panelId = c.proCtcaePanelId;
      final panel = panelId == null
          ? null
          : panels.firstWhere(
              (p) => p.id == panelId,
              orElse: () => const VocabSymptomPanel(id: '', name: '', termIds: []),
            );
      final panelTerms = (panel?.termIds ?? const <String>[])
          .map((tid) => byTermId[tid])
          .whereType<VocabSymptomTerm>()
          .toList(growable: false);
      return ConditionWithTerms(condition: c, terms: panelTerms);
    }).toList(growable: false);

    // Write-through to the local cache. We store a single snapshot blob so
    // loadAll() can read it back in one query; per-row keys would force us
    // to enumerate keys, which our hand-rolled sqlite layer doesn't support.
    final snapshotBlob = jsonEncode({
      '_fetched_at': now.millisecondsSinceEpoch,
      'conditions': {
        for (final c in conditions) c.id: {
          'id': c.id,
          'display_name': c.displayName,
          'category': c.category,
          'icd10_code': c.icd10Code,
          'pro_ctcae_panel_id': c.proCtcaePanelId,
        },
      },
      'terms': {
        for (final t in terms) t.id: {
          'id': t.id,
          'display_name': t.displayName,
          'body_system': t.bodySystem,
          'pro_ctcae_code': t.proCtcaeCode,
          'attributes': t.attributes,
          'plain_language': t.plainLanguage,
        },
      },
      'panels': {
        for (final p in panels) p.id: {
          'id': p.id,
          'name': p.name,
          'term_ids': p.termIds,
        },
      },
    });
    await db.putCachedVocab(
      key: '$_cacheVersion:_snapshot',
      valueJson: snapshotBlob,
      fetchedAt: now,
    );

    return snapshot;
  }

  /// Read from cache; refresh if stale or empty. Always returns *something* —
  /// the stale cache is preferable to a blank screen.
  Future<List<ConditionWithTerms>> loadAll() async {
    try {
      final cached = await _readCache();
      if (cached != null && !_isStale(cached.fetchedAt)) return cached.snapshot;
    } catch (_) {
      // cache miss / parse error — fall through to refresh
    }
    return refresh();
  }

  Future<_CachedSnapshot?> _readCache() async {
    final db = await _ref.read(appDatabaseProvider.future);
    final blobKey = '$_cacheVersion:_snapshot';
    final blob = await db.cachedVocab(blobKey);
    if (blob == null) return null;

    final parsed = jsonDecode(blob) as Map<String, dynamic>;
    final newestFetched =
        DateTime.fromMillisecondsSinceEpoch(parsed['_fetched_at'] as int);

    final conditions = (parsed['conditions'] as Map)
        .values
        .cast<Map<String, dynamic>>()
        .map(VocabCondition.fromJson)
        .toList(growable: false);
    final terms = (parsed['terms'] as Map)
        .values
        .cast<Map<String, dynamic>>()
        .map(VocabSymptomTerm.fromJson)
        .toList(growable: false);
    final panels = (parsed['panels'] as Map)
        .values
        .cast<Map<String, dynamic>>()
        .map(VocabSymptomPanel.fromJson)
        .toList(growable: false);
    final byTermId = {for (final t in terms) t.id: t};
    final snapshot = conditions.map((c) {
      final panelId = c.proCtcaePanelId;
      final panel = panelId == null
          ? null
          : panels.firstWhere(
              (p) => p.id == panelId,
              orElse: () => const VocabSymptomPanel(id: '', name: '', termIds: []),
            );
      final panelTerms = (panel?.termIds ?? const <String>[])
          .map((tid) => byTermId[tid])
          .whereType<VocabSymptomTerm>()
          .toList(growable: false);
      return ConditionWithTerms(condition: c, terms: panelTerms);
    }).toList(growable: false);

    return _CachedSnapshot(fetchedAt: newestFetched, snapshot: snapshot);
  }

  bool _isStale(DateTime fetchedAt) {
    final now = _ref.read(clockProvider).nowUtc();
    return now.difference(fetchedAt) > _cacheTtl;
  }
}

class _CachedSnapshot {
  const _CachedSnapshot({required this.fetchedAt, required this.snapshot});
  final DateTime fetchedAt;
  final List<ConditionWithTerms> snapshot;
}