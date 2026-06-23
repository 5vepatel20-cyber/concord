import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/condition.dart';
import '../../data/repositories/vocab_repository.dart';
import '../../theme/tokens.dart';

class ConditionPickerScreen extends ConsumerStatefulWidget {
  const ConditionPickerScreen({super.key});

  @override
  ConsumerState<ConditionPickerScreen> createState() =>
      _ConditionPickerScreenState();
}

class _ConditionPickerScreenState extends ConsumerState<ConditionPickerScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _categoryLabels = {
    'oncology': 'Cancer types',
    'cardiometabolic': 'Cardiovascular & metabolic',
    'autoimmune': 'Autoimmune',
    'respiratory': 'Respiratory',
    'mental_health': 'Mental health',
    'other': 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final vocabAsync = ref.watch(vocabSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Select condition')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s5,
                Space.s3,
                Space.s5,
                Space.s2,
              ),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search conditions…',
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: vocabAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Could not load conditions: $e')),
                data: (snapshot) {
                  final filtered = _query.isEmpty
                      ? snapshot
                      : snapshot.where((c) {
                          final name = c.condition.displayName.toLowerCase();
                          final code =
                              c.condition.icd10Code?.toLowerCase() ?? '';
                          return name.contains(_query) || code.contains(_query);
                        }).toList();

                  final grouped = <String, List<ConditionWithTerms>>{};
                  for (final c in filtered) {
                    grouped.putIfAbsent(c.condition.category, () => []);
                    grouped[c.condition.category]!.add(c);
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _query.isEmpty
                            ? 'No conditions loaded.'
                            : 'No conditions match "$_query".',
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: Neutrals.hint,
                        ),
                      ),
                    );
                  }

                  return ListView(
                    children: [
                      for (final entry in grouped.entries) ...[
                        if (entry.value.isNotEmpty) ...[
                          Padding(
                            padding: EdgeInsets.only(
                              top: entry.key == grouped.keys.first
                                  ? 0
                                  : Space.s3,
                              bottom: Space.s1,
                              left: Space.s5,
                            ),
                            child: Text(
                              _categoryLabels[entry.key] ?? entry.key,
                              style: t.textTheme.labelSmall?.copyWith(
                                color: Neutrals.hint,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          for (final c in entry.value)
                            ListTile(
                              title: Text(c.condition.displayName),
                              subtitle: c.condition.icd10Code == null
                                  ? null
                                  : Text('ICD-10: ${c.condition.icd10Code}'),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 18,
                              ),
                              onTap: () => Navigator.pop(context, {
                                'id': c.condition.id,
                                'label': c.condition.displayName,
                              }),
                            ),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
