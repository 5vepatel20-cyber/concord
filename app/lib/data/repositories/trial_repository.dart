import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../supabase/supabase_provider.dart';

final trialRepositoryProvider = Provider<TrialRepository>((ref) {
  return TrialRepository(ref);
});

class TrialStudy {
  const TrialStudy({
    required this.nctId,
    required this.title,
    required this.status,
    required this.phase,
    required this.conditions,
    required this.interventions,
    this.location,
    required this.briefSummary,
    required this.lastUpdated,
    required this.url,
  });

  factory TrialStudy.fromJson(Map<String, dynamic> j) => TrialStudy(
    nctId: j['nctId'] as String? ?? '',
    title: j['title'] as String? ?? '',
    status: j['status'] as String? ?? '',
    phase: j['phase'] as String? ?? '',
    conditions: (j['conditions'] as List<dynamic>?)?.cast<String>() ?? [],
    interventions: (j['interventions'] as List<dynamic>?)?.cast<String>() ?? [],
    location: j['location'] as String?,
    briefSummary: j['briefSummary'] as String? ?? '',
    lastUpdated: j['lastUpdated'] as String? ?? '',
    url: j['url'] as String? ?? '',
  );

  final String nctId;
  final String title;
  final String status;
  final String phase;
  final List<String> conditions;
  final List<String> interventions;
  final String? location;
  final String briefSummary;
  final String lastUpdated;
  final String url;

  String get phaseLabel {
    switch (phase) {
      case 'EARLY1':
        return 'Early Phase 1';
      case 'PHASE1':
        return 'Phase 1';
      case 'PHASE2':
        return 'Phase 2';
      case 'PHASE3':
        return 'Phase 3';
      case 'PHASE4':
        return 'Phase 4';
      default:
        return phase;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'RECRUITING':
        return 'Recruiting';
      case 'ACTIVE_NOT_RECRUITING':
        return 'Active, not recruiting';
      case 'COMPLETED':
        return 'Completed';
      case 'ENROLLING_BY_INVITATION':
        return 'Enrolling by invitation';
      case 'NOT_YET_RECRUITING':
        return 'Not yet recruiting';
      case 'AVAILABLE':
        return 'Available';
      case 'WITHDRAWN':
        return 'Withdrawn';
      case 'SUSPENDED':
        return 'Suspended';
      case 'TERMINATED':
        return 'Terminated';
      default:
        return status;
    }
  }
}

class TrialMatch {
  const TrialMatch({
    required this.nctId,
    required this.status,
    required this.createdAt,
  });

  factory TrialMatch.fromJson(Map<String, dynamic> j) => TrialMatch(
    nctId: j['nct_id'] as String? ?? '',
    status: j['status'] as String? ?? '',
    createdAt: j['created_at'] as String? ?? '',
  );

  final String nctId;
  final String status;
  final String createdAt;
}

class TrialRepository {
  TrialRepository(this._ref);
  final Ref _ref;

  Map<String, String> _authHeader() {
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) throw StateError('Not authenticated');
    return {'Authorization': 'Bearer ${session.accessToken}'};
  }

  String get _apiBase => _ref.read(apiBaseUrlProvider);

  Future<List<TrialStudy>> search({
    required String query,
    bool recruitingOnly = true,
    int maxResults = 20,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_apiBase/api/trials/search'),
          headers: {'Content-Type': 'application/json', ..._authHeader()},
          body: jsonEncode({
            'query': query,
            'recruitingOnly': recruitingOnly,
            'maxResults': maxResults,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final msg =
          (jsonDecode(response.body) as Map<String, dynamic>)['error']
              as String? ??
          'Search failed';
      throw Exception(msg);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = (body['studies'] as List<dynamic>?) ?? [];
    return raw
        .map((s) => TrialStudy.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(String nctId, {String status = 'saved'}) async {
    final res = await http
        .post(
          Uri.parse('$_apiBase/api/trials/save'),
          headers: {'Content-Type': 'application/json', ..._authHeader()},
          body: jsonEncode({'nct_id': nctId, 'status': status}),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw Exception('Failed to save trial');
    }
  }

  Future<List<TrialMatch>> listMatches({String? status}) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    final uri = Uri.parse(
      '$_apiBase/api/trials/list',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    final res = await http
        .get(uri, headers: _authHeader())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['matches'] as List<dynamic>?) ?? [];
    return raw
        .map((m) => TrialMatch.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<Set<String>> savedNctIds() async {
    final res = await http
        .get(
          Uri.parse('$_apiBase/api/trials/list?status=saved'),
          headers: _authHeader(),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) return {};
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['matches'] as List<dynamic>?) ?? [];
    return raw
        .map((m) => (m as Map<String, dynamic>)['nct_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }
}
