import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class TrialSearchScreen extends ConsumerStatefulWidget {
  const TrialSearchScreen({super.key});

  @override
  ConsumerState<TrialSearchScreen> createState() => _TrialSearchScreenState();
}

class _TrialSearchScreenState extends ConsumerState<TrialSearchScreen> {
  final _queryCtrl = TextEditingController();
  bool _recruitingOnly = true;
  List<TrialStudy> _studies = [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _studies = [];
      _searched = true;
    });

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final response = await http
          .post(
            Uri.parse('$apiBase/api/trials/search'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'query': query,
              'recruitingOnly': _recruitingOnly,
              'maxResults': 20,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = (body['studies'] as List<dynamic>?) ?? [];
        setState(() {
          _studies = raw.map((s) => TrialStudy.fromJson(s as Map<String, dynamic>)).toList();
        });
      } else {
        final msg = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String? ?? 'Search failed';
        setState(() => _error = msg);
      }
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
      appBar: AppBar(
        title: const Text('Clinical Trials'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('About'),
                content: const Text(
                  'Search ClinicalTrials.gov for studies relevant to your '
                  'condition. Discuss any trial you\'re interested in with '
                  'your care team.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Got it'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Container(
              padding: const EdgeInsets.fromLTRB(Space.s5, Space.s3, Space.s5, Space.s2),
              decoration: BoxDecoration(
                color: t.colorScheme.surface,
                border: Border(bottom: BorderSide(color: Neutrals.mist)),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _queryCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Search trials (e.g. "breast cancer")',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _queryCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _queryCtrl.clear();
                                setState(() => _searched = false);
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s2),
                  Row(
                    children: [
                      SizedBox(
                        height: 32,
                        child: FilterChip(
                          label: const Text('Recruiting only', style: TextStyle(fontSize: 12)),
                          selected: _recruitingOnly,
                          onSelected: (v) => setState(() => _recruitingOnly = v),
                        ),
                      ),
                      const SizedBox(width: Space.s2),
                      FilledButton(
                        onPressed: _loading ? null : _search,
                        child: _loading
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Search'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Results
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Space.s6),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: t.textTheme.bodyMedium
                                    ?.copyWith(color: SeverityColors.severe)),
                          ),
                        )
                      : !_searched
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(Space.s6),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.medical_services_outlined,
                                        size: 48, color: Neutrals.hint),
                                    const SizedBox(height: Space.s3),
                                    Text('Search for clinical trials',
                                        style: t.textTheme.titleMedium),
                                    const SizedBox(height: Space.s2),
                                    Text(
                                      'Enter a condition or keyword to find relevant studies.',
                                      textAlign: TextAlign.center,
                                      style: t.textTheme.bodySmall
                                          ?.copyWith(color: Neutrals.slate),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _studies.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(Space.s6),
                                    child: Text('No trials found.',
                                        style: t.textTheme.bodyMedium),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      Space.s5, Space.s3, Space.s5, Space.s10),
                                  itemCount: _studies.length,
                                  itemBuilder: (context, i) =>
                                      _TrialCard(study: _studies[i]),
                                ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrialStudy {
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

  TrialStudy({
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
        interventions:
            (j['interventions'] as List<dynamic>?)?.cast<String>() ?? [],
        location: j['location'] as String?,
        briefSummary: j['briefSummary'] as String? ?? '',
        lastUpdated: j['lastUpdated'] as String? ?? '',
        url: j['url'] as String? ?? '',
      );

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

class _TrialCard extends StatelessWidget {
  const _TrialCard({required this.study});
  final TrialStudy study;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isRecruiting = study.status == 'RECRUITING';

    return Card(
      margin: const EdgeInsets.only(bottom: Space.s3),
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(study.title, style: t.textTheme.titleSmall),
                ),
                const SizedBox(width: Space.s2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.s2, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRecruiting
                        ? SeverityColors.none.withValues(alpha: 0.12)
                        : Neutrals.mist,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    isRecruiting ? 'Open' : study.statusLabel,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: isRecruiting ? SeverityColors.none : Neutrals.slate,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s2),
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s1,
              children: [
                _Tag(label: study.phaseLabel),
                if (study.location != null) _Tag(label: study.location!),
              ],
            ),
            if (study.briefSummary.isNotEmpty) ...[
              const SizedBox(height: Space.s2),
              Text(
                study.briefSummary,
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: Space.s3),
            Row(
              children: [
                Icon(Icons.medical_services_outlined,
                    size: 14, color: Neutrals.hint),
                const SizedBox(width: Space.s1),
                Expanded(
                  child: Text(
                    study.conditions.take(3).join(', '),
                    style: t.textTheme.bodySmall?.copyWith(color: Neutrals.hint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening ${study.nctId}…'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View on CT.gov'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 2),
      decoration: BoxDecoration(
        color: BrandColors.concordBlueTint,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: BrandColors.concordBlue,
            ),
      ),
    );
  }
}
