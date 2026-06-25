import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/trial_repository.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class TrialSearchScreen extends ConsumerStatefulWidget {
  const TrialSearchScreen({super.key});

  @override
  ConsumerState<TrialSearchScreen> createState() => _TrialSearchScreenState();
}

class _TrialSearchScreenState extends ConsumerState<TrialSearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _queryCtrl = TextEditingController();
  bool _recruitingOnly = true;
  List<TrialStudy> _studies = [];
  Set<String> _savedNctIds = {};
  List<TrialMatch> _savedMatches = [];
  bool _loading = false;
  bool _loadingSaved = false;
  String? _error;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging && _tabCtrl.index == 1) {
        _loadSaved();
      }
    });
    _loadSaved();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    setState(() => _loadingSaved = true);
    try {
      final repo = ref.read(trialRepositoryProvider);
      final ids = await repo.savedNctIds();
      final matches = await repo.listMatches();
      if (mounted) {
        setState(() {
          _savedNctIds = ids;
          _savedMatches = matches;
          _loadingSaved = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSaved = false);
    }
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
      final repo = ref.read(trialRepositoryProvider);
      final results = await repo.search(
        query: query,
        recruitingOnly: _recruitingOnly,
      );
      if (!mounted) return;
      setState(() => _studies = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleSave(TrialStudy study) async {
    final repo = ref.read(trialRepositoryProvider);
    final saved = _savedNctIds.contains(study.nctId);
    try {
      if (saved) {
        await repo.save(study.nctId, status: 'dismissed');
      } else {
        await repo.save(study.nctId);
      }
      await _loadSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${saved ? "unsave" : "save"} trial'),
          ),
        );
      }
    }
  }

  Future<void> _dismiss(TrialStudy study) async {
    try {
      final repo = ref.read(trialRepositoryProvider);
      await repo.save(study.nctId, status: 'dismissed');
      setState(() => _studies.removeWhere((s) => s.nctId == study.nctId));
      await _loadSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to dismiss trial')),
        );
      }
    }
  }

  Future<void> _unsave(TrialMatch match) async {
    try {
      final repo = ref.read(trialRepositoryProvider);
      await repo.save(match.nctId, status: 'dismissed');
      await _loadSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to remove trial')));
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Trials'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Search'),
            Tab(text: 'Saved'),
          ],
        ),
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
      body: TabBarView(
        controller: _tabCtrl,
        children: [_buildSearchTab(t), _buildSavedTab(t)],
      ),
    );
  }

  Widget _buildSearchTab(ThemeData t) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              Space.s3,
              Space.s5,
              Space.s2,
            ),
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
                        label: const Text(
                          'Recruiting only',
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: _recruitingOnly,
                        onSelected: (v) => setState(() => _recruitingOnly = v),
                      ),
                    ),
                    const SizedBox(width: Space.s2),
                    FilledButton(
                      onPressed: _loading ? null : _search,
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Search'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.s6),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: SeverityColors.severe,
                        ),
                      ),
                    ),
                  )
                : !_searched
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.s6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.medical_services_outlined,
                            size: 48,
                            color: Neutrals.hint,
                          ),
                          const SizedBox(height: Space.s3),
                          Text(
                            'Search for clinical trials',
                            style: t.textTheme.titleMedium,
                          ),
                          const SizedBox(height: Space.s2),
                          Text(
                            'Enter a condition or keyword to find '
                            'relevant studies.',
                            textAlign: TextAlign.center,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: Neutrals.slate,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _studies.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.s6),
                      child: Text(
                        'No trials found.',
                        style: t.textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      Space.s5,
                      Space.s3,
                      Space.s5,
                      Space.s10,
                    ),
                    itemCount: _studies.length,
                    itemBuilder: (context, i) => _TrialCard(
                      study: _studies[i],
                      isSaved: _savedNctIds.contains(_studies[i].nctId),
                      onSave: () => _toggleSave(_studies[i]),
                      onDismiss: () => _dismiss(_studies[i]),
                      onOpen: () => _openUrl(_studies[i].url),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedTab(ThemeData t) {
    if (_loadingSaved) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_savedMatches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.s6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_outline, size: 48, color: Neutrals.hint),
              const SizedBox(height: Space.s3),
              Text('No saved trials', style: t.textTheme.titleMedium),
              const SizedBox(height: Space.s2),
              Text(
                'Save trials from the search tab to see them here.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s3,
        Space.s5,
        Space.s10,
      ),
      itemCount: _savedMatches.length,
      itemBuilder: (context, i) {
        final match = _savedMatches[i];
        final ctUrl = 'https://clinicaltrials.gov/study/${match.nctId}';
        final createdDate = match.createdAt.isNotEmpty
            ? DateFormat.yMMMd().format(DateTime.parse(match.createdAt))
            : '';
        return Card(
          margin: const EdgeInsets.only(bottom: Space.s3),
          child: Padding(
            padding: const EdgeInsets.all(Space.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(match.nctId, style: t.textTheme.titleSmall),
                    ),
                    if (createdDate.isNotEmpty)
                      Text(
                        createdDate,
                        style: t.textTheme.labelSmall?.copyWith(
                          color: Neutrals.hint,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.s3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openUrl(ctUrl),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('View on CT.gov'),
                    ),
                    const SizedBox(width: Space.s1),
                    TextButton.icon(
                      onPressed: () => _unsave(match),
                      icon: const Icon(Icons.bookmark_remove, size: 16),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(
                        foregroundColor: SeverityColors.severe,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrialCard extends StatelessWidget {
  const _TrialCard({
    required this.study,
    required this.isSaved,
    required this.onSave,
    required this.onDismiss,
    required this.onOpen,
  });

  final TrialStudy study;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

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
                    horizontal: Space.s2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isRecruiting
                        ? SeverityColors.none.withValues(alpha: 0.12)
                        : Neutrals.mist,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    isRecruiting ? 'Open' : study.statusLabel,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: isRecruiting
                          ? SeverityColors.none
                          : Neutrals.slate,
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
                Icon(
                  Icons.medical_services_outlined,
                  size: 14,
                  color: Neutrals.hint,
                ),
                const SizedBox(width: Space.s1),
                Expanded(
                  child: Text(
                    study.conditions.take(3).join(', '),
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.hint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onSave,
                  icon: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: isSaved ? BrandColors.concordBlue : null,
                  ),
                  tooltip: isSaved ? 'Unsave' : 'Save',
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss',
                ),
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View on CT.gov'),
                ),
              ],
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
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: BrandColors.concordBlue),
      ),
    );
  }
}
