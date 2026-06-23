import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';

/// Caregiver dashboard — lists patients the current user is a caregiver for
/// and provides actions including proxy symptom logging (SYM-08).
class CaregiverDashboardScreen extends ConsumerStatefulWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  ConsumerState<CaregiverDashboardScreen> createState() =>
      _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState
    extends ConsumerState<CaregiverDashboardScreen> {
  List<Map<String, dynamic>> _patients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final res = await http.get(
        Uri.parse('$apiBase/api/caregiver/relationships'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (body['as_caregiver'] as List<dynamic>?) ?? [];
      setState(() {
        _patients = raw.cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Caregiver dashboard')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: SeverityColors.severe,
                      ),
                      const SizedBox(height: Space.s3),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: SeverityColors.severe,
                        ),
                      ),
                      const SizedBox(height: Space.s3),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _patients.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.favorite_outline,
                        size: 48,
                        color: Neutrals.hint,
                      ),
                      const SizedBox(height: Space.s3),
                      Text('No patients yet', style: t.textTheme.titleMedium),
                      const SizedBox(height: Space.s2),
                      Text(
                        'You are not linked as a caregiver for anyone. '
                        'Ask a patient to invite you from their care team settings.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: Neutrals.slate,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s5,
                    Space.s3,
                    Space.s5,
                    Space.s10,
                  ),
                  children: [
                    Text(
                      'Your patients',
                      style: t.textTheme.titleSmall?.copyWith(
                        color: Neutrals.slate,
                      ),
                    ),
                    const SizedBox(height: Space.s2),
                    ..._patients.map(
                      (p) => _PatientTile(
                        patient: p,
                        onLogSymptoms: () => _openLog(p),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _openLog(Map<String, dynamic> patient) {
    final p = patient['patient'] as Map<String, dynamic>?;
    if (p == null) return;
    context.push(
      '/caregiver/log/${p['id']}',
      extra: {'name': p['full_name'] ?? p['email'] ?? 'Patient'},
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({required this.patient, required this.onLogSymptoms});
  final Map<String, dynamic> patient;
  final VoidCallback onLogSymptoms;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = patient['patient'] as Map<String, dynamic>?;
    final name =
        p?['full_name'] as String? ?? p?['email'] as String? ?? 'Unknown';
    final relationship = patient['relationship'] as String? ?? '';
    final createdAt = patient['created_at'] as String?;
    final perms = patient['permissions'] as Map<String, dynamic>? ?? {};
    final canLog = perms['can_log'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: Space.s2),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: BrandColors.concordBlueTint,
          child: Icon(Icons.person, color: BrandColors.concordBlue),
        ),
        title: Text(name, style: t.textTheme.titleSmall),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _relationshipLabel(relationship),
              style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
            ),
            if (createdAt != null)
              Text(
                'Since ${DateFormat.MMMd().format(DateTime.parse(createdAt))}',
                style: t.textTheme.labelSmall?.copyWith(color: Neutrals.hint),
              ),
          ],
        ),
        trailing: canLog
            ? FilledButton.tonalIcon(
                onPressed: onLogSymptoms,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Log'),
              )
            : null,
      ),
    );
  }

  String _relationshipLabel(String r) {
    switch (r) {
      case 'spouse':
        return 'Spouse';
      case 'child':
        return 'Child';
      case 'parent':
        return 'Parent';
      case 'friend':
        return 'Friend';
      case 'clinician':
        return 'Clinician';
      case 'care_navigator':
        return 'Care navigator';
      default:
        return r;
    }
  }
}
