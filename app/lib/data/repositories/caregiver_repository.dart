import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/supabase/supabase_provider.dart';

final caregiverRepositoryProvider = Provider<CaregiverRepository>((ref) {
  return CaregiverRepository(ref);
});

class CaregiverRepository {
  CaregiverRepository(this.ref);
  final Ref ref;

  Future<http.Response> _authPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final apiBase = ref.read(apiBaseUrlProvider);
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    return http
        .post(
          Uri.parse('$apiBase$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<http.Response> _authGet(String path) async {
    final apiBase = ref.read(apiBaseUrlProvider);
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    return http
        .get(
          Uri.parse('$apiBase$path'),
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<Map<String, dynamic>> invite({
    required String email,
    required String relationship,
    Map<String, bool>? permissions,
  }) async {
    final res = await _authPost('/api/caregiver/invite', {
      'email': email,
      'relationship': relationship,
      if (permissions != null) 'permissions': permissions,
    });
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(body['error']?['message'] ?? 'Invite failed');
    }
    return body;
  }

  Future<Map<String, dynamic>> list() async {
    final res = await _authGet('/api/caregiver/relationships');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error']?['message'] ?? 'Failed to load');
    }
    return body;
  }

  Future<void> revoke(String relationshipId) async {
    final res = await _authPost('/api/caregiver/revoke', {
      'relationship_id': relationshipId,
    });
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error']?['message'] ?? 'Revoke failed');
    }
  }
}
