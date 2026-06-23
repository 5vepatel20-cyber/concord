import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';

final _alertListProvider = FutureProvider.autoDispose<List<AlertItem>>((
  ref,
) async {
  final supabase = ref.watch(supabaseClientProvider);
  final session = supabase.auth.currentSession;
  if (session == null) return [];
  final apiBase = ref.read(apiBaseUrlProvider);
  final res = await http
      .get(
        Uri.parse('$apiBase/api/alerts?limit=50'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      )
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return [];
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final raw = body['alerts'] as List<dynamic>? ?? [];
  return raw.map((e) => AlertItem.fromJson(e as Map<String, dynamic>)).toList();
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

class AlertListScreen extends ConsumerWidget {
  const AlertListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final alertsAsync = ref.watch(_alertListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: SafeArea(
        child: alertsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (alerts) {
            if (alerts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: Colors.green.shade300,
                    ),
                    const SizedBox(height: Space.s3),
                    Text('No alerts', style: t.textTheme.titleMedium),
                    const SizedBox(height: Space.s1),
                    Text(
                      'All clear — no symptom alerts right now.',
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: Neutrals.slate,
                      ),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(_alertListProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.all(Space.s4),
                itemCount: alerts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _AlertTile(alert: alerts[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});
  final AlertItem alert;

  Color _severityColor() {
    switch (alert.severityLevel) {
      case 'critical':
      case 'severe':
        return SeverityColors.severe;
      case 'moderate':
        return SeverityColors.moderate;
      case 'mild':
        return SeverityColors.mild;
      default:
        return Neutrals.slate;
    }
  }

  String _dateLabel() {
    if (alert.createdAt.length < 10) return '';
    final date = alert.createdAt.substring(0, 10);
    final time = alert.createdAt.length > 16
        ? alert.createdAt.substring(11, 16)
        : '';
    return '$date $time';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _severityColor();
    final isOpen = alert.status == 'open';

    return ListTile(
      leading: Icon(
        isOpen ? Icons.warning_amber_rounded : Icons.check_circle_outline,
        color: isOpen ? color : Colors.green,
      ),
      title: Text(
        alert.severityLevel.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(_dateLabel()),
      trailing: isOpen
          ? TextButton(
              onPressed: () async {
                final supabase = ref.read(supabaseClientProvider);
                final session = supabase.auth.currentSession;
                if (session == null) return;
                final apiBase = ref.read(apiBaseUrlProvider);
                try {
                  await http.post(
                    Uri.parse('$apiBase/api/alerts/acknowledge'),
                    headers: {
                      'Content-Type': 'application/json',
                      'Authorization': 'Bearer ${session.accessToken}',
                    },
                    body: jsonEncode({'alert_id': alert.id}),
                  );
                  if (context.mounted) {
                    ref.refresh(_alertListProvider.future);
                  }
                } catch (_) {}
              },
              child: const Text('Acknowledge'),
            )
          : Text(
              'Acknowledged',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
    );
  }
}
