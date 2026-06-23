import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class AdherenceStat {
  const AdherenceStat({
    required this.medicationId,
    required this.displayName,
    this.dose,
    this.unit,
    required this.days7,
    required this.days30,
  });

  factory AdherenceStat.fromJson(Map<String, dynamic> j) => AdherenceStat(
    medicationId: j['medication_id'] as String,
    displayName: j['display_name'] as String? ?? '',
    dose: j['dose'] as String?,
    unit: j['unit'] as String?,
    days7: _WindowStat.fromJson(j['days_7'] as Map<String, dynamic>? ?? {}),
    days30: _WindowStat.fromJson(j['days_30'] as Map<String, dynamic>? ?? {}),
  );

  final String medicationId;
  final String displayName;
  final String? dose;
  final String? unit;
  final _WindowStat days7;
  final _WindowStat days30;
}

class _WindowStat {
  const _WindowStat({
    required this.taken,
    required this.total,
    required this.pct,
  });

  factory _WindowStat.fromJson(Map<String, dynamic> j) => _WindowStat(
    taken: j['taken'] as int? ?? 0,
    total: j['total'] as int? ?? 0,
    pct: j['pct'] as int? ?? 0,
  );

  final int taken;
  final int total;
  final int pct;
}

final _adherenceStatsProvider = FutureProvider.autoDispose<List<AdherenceStat>>(
  (ref) async {
    final supabase = ref.watch(supabaseClientProvider);
    final session = supabase.auth.currentSession;
    if (session == null) return [];
    final apiBase = ref.read(apiBaseUrlProvider);
    final res = await http
        .get(
          Uri.parse('$apiBase/api/medications/adherence-stats'),
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['stats'] as List<dynamic>? ?? [];
    return raw
        .map((e) => AdherenceStat.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);

Color _adherenceColor(int pct) {
  if (pct >= 80) return Colors.green;
  if (pct >= 50) return SeverityColors.moderate;
  return SeverityColors.severe;
}

class AdherenceDashboardScreen extends ConsumerWidget {
  const AdherenceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final statsAsync = ref.watch(_adherenceStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Adherence')),
      body: SafeArea(
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (stats) {
            if (stats.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.medication_outlined,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: Space.s3),
                    Text('No medications yet', style: t.textTheme.titleMedium),
                    const SizedBox(height: Space.s1),
                    Text(
                      'Add medications to start tracking adherence.',
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: Neutrals.slate,
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () => ref.refresh(_adherenceStatsProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(Space.s4),
                children: [
                  Text('Medication adherence', style: t.textTheme.titleMedium),
                  const SizedBox(height: Space.s1),
                  Text(
                    'Shows how consistently you are taking your medications.',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.slate,
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  for (final stat in stats) ...[
                    _StatCard(stat: stat),
                    const SizedBox(height: Space.s3),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final AdherenceStat stat;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(stat.displayName, style: t.textTheme.titleSmall),
                ),
                if (stat.dose != null)
                  Text(
                    '${stat.dose}${stat.unit ?? ''}',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.slate,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.s4),
            Row(
              children: [
                Expanded(
                  child: _WindowBar(label: '7 days', stat: stat.days7),
                ),
                const SizedBox(width: Space.s4),
                Expanded(
                  child: _WindowBar(label: '30 days', stat: stat.days30),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowBar extends StatelessWidget {
  const _WindowBar({required this.label, required this.stat});
  final String label;
  final _WindowStat stat;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = _adherenceColor(stat.pct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s2),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: stat.total > 0 ? stat.pct / 100.0 : 0,
            minHeight: 24,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: Space.s1),
        Text(
          '${stat.pct}%',
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
        Text(
          '${stat.taken}/${stat.total} doses',
          style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
        ),
      ],
    );
  }
}
