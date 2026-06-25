import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../supabase/supabase_provider.dart';

final alertRepositoryProvider = Provider<AlertRepository>((ref) {
  return AlertRepository(ref);
});

final alertListProvider = FutureProvider.autoDispose<List<AlertItem>>((
  ref,
) async {
  return ref.read(alertRepositoryProvider).list();
});

class AlertItem {
  const AlertItem({
    required this.id,
    required this.severityLevel,
    required this.status,
    required this.createdAt,
    this.acknowledgedAt,
    this.ruleTermId,
  });

  factory AlertItem.fromJson(Map<String, dynamic> j) => AlertItem(
    id: j['id'] as String,
    severityLevel: j['severity_level'] as String? ?? 'info',
    status: j['status'] as String? ?? 'open',
    createdAt: j['created_at'] as String? ?? '',
    acknowledgedAt: j['acknowledged_at'] as String?,
    ruleTermId: (j['rule'] as Map<String, dynamic>?)?['term_id'] as String?,
  );

  final String id;
  final String severityLevel;
  final String status;
  final String createdAt;
  final String? acknowledgedAt;
  final String? ruleTermId;
}

class EscalationPolicy {
  const EscalationPolicy({
    required this.id,
    required this.name,
    required this.severityThreshold,
    required this.timeRestriction,
    required this.targetRole,
    required this.notificationChannel,
    required this.priority,
    required this.delayMinutes,
    required this.active,
  });

  factory EscalationPolicy.fromJson(Map<String, dynamic> j) {
    return EscalationPolicy(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      severityThreshold: j['severity_threshold'] as String? ?? 'urgent',
      timeRestriction: j['time_restriction'] as String? ?? 'always',
      targetRole: j['target_role'] as String? ?? 'caregiver',
      notificationChannel: j['notification_channel'] as String? ?? 'email',
      priority: j['priority'] as int? ?? 0,
      delayMinutes: j['delay_minutes'] as int? ?? 0,
      active: j['active'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final String severityThreshold;
  final String timeRestriction;
  final String targetRole;
  final String notificationChannel;
  final int priority;
  final int delayMinutes;
  final bool active;
}

class AlertRepository {
  AlertRepository(this._ref);
  final Ref _ref;

  Map<String, String> _authHeader() {
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) throw StateError('Not authenticated');
    return {'Authorization': 'Bearer ${session.accessToken}'};
  }

  String get _apiBase => _ref.read(apiBaseUrlProvider);

  Future<List<AlertItem>> list({int limit = 50}) async {
    final res = await http
        .get(
          Uri.parse('$_apiBase/api/alerts?limit=$limit'),
          headers: _authHeader(),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['alerts'] as List<dynamic>? ?? [];
    return raw
        .map((e) => AlertItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> acknowledge(String alertId) async {
    await http
        .post(
          Uri.parse('$_apiBase/api/alerts/acknowledge'),
          headers: {'Content-Type': 'application/json', ..._authHeader()},
          body: jsonEncode({'alert_id': alertId}),
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<List<EscalationPolicy>> fetchPolicies() async {
    final res = await http
        .get(Uri.parse('$_apiBase/api/alerts/policies'), headers: _authHeader())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['policies'] as List<dynamic>?) ?? [];
    return raw
        .map((e) => EscalationPolicy.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createPolicy(Map<String, dynamic> policy) async {
    final res = await http
        .post(
          Uri.parse('$_apiBase/api/alerts/policies'),
          headers: {'Content-Type': 'application/json', ..._authHeader()},
          body: jsonEncode(policy),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 201) {
      final msg =
          (jsonDecode(res.body) as Map<String, dynamic>)['error']
              as Map<String, dynamic>? ??
          {};
      throw Exception((msg['message'] as String?) ?? 'Failed to create policy');
    }
  }

  Future<void> deletePolicy(String id) async {
    await http
        .delete(
          Uri.parse('$_apiBase/api/alerts/policies/$id'),
          headers: _authHeader(),
        )
        .timeout(const Duration(seconds: 15));
  }
}
