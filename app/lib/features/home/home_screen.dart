// Home dashboard — the patient's daily landing surface.
//
// Shows:
//   - Today's date + a "Good morning" greeting (uses the user's first name)
//   - Quick action buttons: Log, Report, Atlas
//   - SYM-06 worsening symptoms card (hidden when nothing to report)
//   - "Log a symptom" CTA that opens the quick-log bottom sheet
//   - Today's activity (HealthKit / Health Connect snapshot — optional)
//   - Recent symptom logs list with top grade
//   - Latest Atlas nudge

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/health/health_repository.dart';
import '../../core/sync/pending_count_provider.dart';
import '../../theme/tokens.dart';
import '../../data/repositories/report_repository.dart';
import '../../theme/typography.dart';
import '../symptoms/quick_log_screen.dart';
import '../symptoms/quick_log_widget.dart';
import '../symptoms/symptom_history_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _refreshKey = 0;

  Future<void> _onRefresh() async {
    setState(() => _refreshKey++);
  }

  String _firstNameFromEmail(String? email) {
    if (email == null || email.isEmpty) return 'there';
    final local = email.split('@').first;
    final first = local
        .split(RegExp(r'[._\d]'))
        .firstWhere((s) => s.isNotEmpty, orElse: () => local);
    return first[0].toUpperCase() + first.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE, MMM d').format(now);
    final greeting = _greetingFor(now);
    final firstName = _firstNameFromEmail(user?.email);

    return Scaffold(
      appBar: AppBar(
        title: Text(dateLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign out',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Use Profile → Sign out to leave.'),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView(
            key: ValueKey('home_$_refreshKey'),
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              Space.s2,
              Space.s5,
              Space.s6,
            ),
            children: [
              _GreetingRow(greeting: greeting, firstName: firstName),
              const SizedBox(height: Space.s3),
              _QuickActionsRow(),
              const SizedBox(height: Space.s2),
              const _PendingSyncBadge(),
              const SizedBox(height: Space.s2),
              const _WorseningCard(),
              const SizedBox(height: Space.s3),
              const QuickLogWidget(),
              const SizedBox(height: Space.s3),
              TextButton.icon(
                onPressed: () => context.push('/symptom-history'),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('View symptom history'),
              ),
              const SizedBox(height: Space.s5),
              const _TodayActivityCard(),
              const SizedBox(height: Space.s6),
              _Section(
                title: 'Recent reports',
                child: _RecentReportsCard(key: ValueKey('rc_$_refreshKey')),
              ),
              const SizedBox(height: Space.s5),
              _Section(title: 'Atlas says', child: _AtlasNudgeCard()),
            ],
          ),
        ),
      ),
    );
  }

  String _greetingFor(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

/// Greeting row with time-appropriate emoji and today's check-in status chip.
class _GreetingRow extends ConsumerWidget {
  const _GreetingRow({required this.greeting, required this.firstName});

  final String greeting;
  final String firstName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final emoji = switch (greeting) {
      'Good morning' => '🌅',
      'Good afternoon' => '☀️',
      _ => '🌙',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$emoji ', style: t.textTheme.headlineMedium),
            Expanded(
              child: Text(
                '$greeting, $firstName',
                style: t.textTheme.headlineMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s1),
        const _TodayCheckinChip(),
      ],
    );
  }
}

/// Green "Checked in today" chip shown when the patient has logged symptoms today.
class _TodayCheckinChip extends ConsumerStatefulWidget {
  const _TodayCheckinChip();

  @override
  ConsumerState<_TodayCheckinChip> createState() => _TodayCheckinChipState();
}

class _TodayCheckinChipState extends ConsumerState<_TodayCheckinChip> {
  bool _checkedIn = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(reportRepositoryProvider);
      final reports = await repo.listRecent(limit: 1);
      if (!mounted) return;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final checkedIn = reports.any(
        (r) => DateFormat('yyyy-MM-dd').format(r.reportedAt) == today,
      );
      if (mounted) setState(() => _checkedIn = checkedIn);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_checkedIn) return const SizedBox.shrink();
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: SeverityColors.none.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: SeverityColors.none),
          const SizedBox(width: 4),
          Text(
            'Checked in today',
            style: t.textTheme.bodySmall?.copyWith(
              color: SeverityColors.none,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a compact badge when there are pending sync items.
class _PendingSyncBadge extends ConsumerWidget {
  const _PendingSyncBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingSyncCountProvider);
    return pendingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (count) {
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.s2),
          child: Row(
            children: [
              const Icon(Icons.sync, size: 14, color: Neutrals.slate),
              const SizedBox(width: Space.s1),
              Text(
                '$count item${count == 1 ? '' : 's'} waiting to sync',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Neutrals.slate),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// SYM-06: Worsening symptoms card. Shows when one or more symptoms have
/// worsened (grade increased >= 1) or appeared new vs the prior 7-day window.
/// Only renders when there IS a change — otherwise it stays hidden.
class _WorseningCard extends ConsumerStatefulWidget {
  const _WorseningCard();

  @override
  ConsumerState<_WorseningCard> createState() => _WorseningCardState();
}

class _WorseningCardState extends ConsumerState<_WorseningCard> {
  OnePagerReport? _report;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(reportRepositoryProvider);
      final report = await repo.generateOnePager(days: 7);
      if (mounted) setState(() => _report = report);
    } catch (_) {
      // Silently hide on error — non-blocking dashboard card.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _report == null) return const SizedBox.shrink();
    final worsening = _report!.newOrWorsening;
    if (worsening.isEmpty) return const SizedBox.shrink();

    final t = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => context.push('/report/generate'),
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 20,
                    color: SeverityColors.moderate,
                  ),
                  const SizedBox(width: Space.s2),
                  Text(
                    '${worsening.length} symptom${worsening.length == 1 ? '' : 's'} need attention',
                    style: t.textTheme.titleSmall?.copyWith(
                      color: SeverityColors.moderate,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s2),
              ...worsening
                  .take(4)
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: Space.s1),
                      child: Row(
                        children: [
                          Icon(
                            s.direction == 'new'
                                ? Icons.add_circle_outline
                                : Icons.arrow_upward,
                            size: 16,
                            color: s.direction == 'new'
                                ? SeverityColors.moderate
                                : SeverityColors.severe,
                          ),
                          const SizedBox(width: Space.s2),
                          Expanded(
                            child: Text(
                              s.termName,
                              style: t.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            s.direction == 'new'
                                ? 'New'
                                : '${s.priorAvgGrade.toStringAsFixed(0)}→${s.currentAvgGrade.toStringAsFixed(0)}',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: Neutrals.slate,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (worsening.length > 4)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s1),
                  child: Text(
                    '+${worsening.length - 4} more',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.slate,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              const SizedBox(height: Space.s2),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Tap to view report',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today-so-far snapshot from Apple Health / Health Connect. Renders a
/// "connect" CTA the first time, then a compact three-stat card.
class _TodayActivityCard extends ConsumerStatefulWidget {
  const _TodayActivityCard();

  @override
  ConsumerState<_TodayActivityCard> createState() => _TodayActivityCardState();
}

class _TodayActivityCardState extends ConsumerState<_TodayActivityCard> {
  bool _checking = true;
  HealthSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _checking = true);
    final repo = ref.read(healthRepositoryProvider);
    final granted = await repo.hasPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _checking = false;
        _snapshot = null;
      });
      return;
    }
    final snap = await repo.fetchTodaySnapshot();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _snapshot = snap;
    });
    // HK-02: best-effort server sync.
    repo.syncToServer(snap);
  }

  Future<void> _connect() async {
    final repo = ref.read(healthRepositoryProvider);
    final granted = await repo.requestPermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Health permission denied.')),
      );
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Card(
        child: SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final s = _snapshot;
    if (s == null || s.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.favorite_outline),
          title: const Text("Connect Apple Health / Health Connect"),
          subtitle: const Text(
            'See steps, sleep, and heart rate alongside your symptoms.',
          ),
          trailing: TextButton(
            onPressed: _connect,
            child: const Text('Connect'),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s3,
          Space.s4,
          Space.s3,
        ),
        child: Row(
          children: [
            _Stat(
              icon: Icons.directions_walk,
              label: 'Steps',
              value: s.steps?.toString() ?? '–',
            ),
            _Stat(
              icon: Icons.favorite_outline,
              label: 'Avg HR',
              value: s.avgHeartRateBpm == null || s.avgHeartRateBpm!.isNaN
                  ? '–'
                  : '${s.avgHeartRateBpm!.round()}',
              suffix: 'bpm',
            ),
            _Stat(
              icon: Icons.bedtime_outlined,
              label: 'Sleep',
              value: s.sleepHoursLastNight == null
                  ? '–'
                  : s.sleepHoursLastNight!.toStringAsFixed(1),
              suffix: 'h',
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: t.colorScheme.primary, size: 22),
          const SizedBox(height: Space.s1),
          RichText(
            text: TextSpan(
              style: t.textTheme.titleMedium,
              children: [
                TextSpan(text: value, style: numericTextStyle),
                if (suffix != null)
                  TextSpan(
                    text: ' $suffix',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.slate,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s1),
          Text(
            label,
            style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.textTheme.titleMedium),
        const SizedBox(height: Space.s2),
        child,
      ],
    );
  }
}

class _RecentReportsCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RecentReportsCard> createState() => _RecentReportsCardState();
}

class _RecentReportsCardState extends ConsumerState<_RecentReportsCard> {
  List<ReportSummary>? _reports;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(reportRepositoryProvider);
      final reports = await repo.listRecent(limit: 5);
      if (mounted) setState(() => _reports = reports);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final reports = _reports;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent symptom logs', style: t.textTheme.titleSmall),
            if (_loading || reports == null || reports.isEmpty) ...[
              const SizedBox(height: Space.s2),
              Text(
                _loading
                    ? 'Loading…'
                    : 'No logs yet. Tap below to log your first symptom.',
                style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
              ),
            ] else ...[
              const SizedBox(height: Space.s2),
              ...reports.take(5).map((r) => _ReportRow(report: r)),
            ],
            const SizedBox(height: Space.s2),
            Row(
              children: [
                if (reports != null && reports.isNotEmpty)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => context.push('/symptom-history'),
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('View all'),
                    ),
                  ),
                Expanded(
                  child: Align(
                    alignment: reports != null && reports.isNotEmpty
                        ? Alignment.centerRight
                        : Alignment.center,
                    child: TextButton.icon(
                      onPressed: () => context.push('/report/generate'),
                      icon: const Icon(Icons.summarize_outlined, size: 18),
                      label: const Text('Generate Summary'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends ConsumerWidget {
  const _ReportRow({required this.report});
  final ReportSummary report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final dateStr = DateFormat('MMM d, h:mm a').format(report.reportedAt);
    final gradeColor = switch (report.topGrade) {
      3 => SeverityColors.severe,
      2 => SeverityColors.moderate,
      1 => SeverityColors.mild,
      _ => Neutrals.slate,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: InkWell(
        onTap: () => context.push('/report/${report.id}'),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s1,
            vertical: Space.s1,
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: gradeColor),
              const SizedBox(width: Space.s2),
              Expanded(child: Text(dateStr, style: t.textTheme.bodySmall)),
              if (report.source != 'self')
                Padding(
                  padding: const EdgeInsets.only(right: Space.s1),
                  child: Text(
                    report.source,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Neutrals.slate,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: gradeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  'Grade ${report.topGrade}',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: gradeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AtlasNudgeCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final now = DateTime.now();
    final isEvening = now.hour >= 17;
    final message = isEvening
        ? 'Ask Atlas how your symptoms compare to last week.'
        : 'Check in with Atlas — get a summary of how you\'re doing.';

    return Card(
      child: InkWell(
        onTap: () => context.go('/atlas'),
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 24)),
              const SizedBox(width: Space.s3),
              Expanded(child: Text(message, style: t.textTheme.bodyMedium)),
              Icon(Icons.chevron_right, color: Neutrals.slate),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick action buttons for common tasks — Log, Report, Atlas, Calendar.
class _QuickActionsRow extends StatelessWidget {
  _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.add_circle_outline,
            label: 'Log',
            onTap: () => QuickLogScreen.show(context),
          ),
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: _ActionButton(
            icon: Icons.summarize_outlined,
            label: 'Report',
            onTap: () => context.push('/report/generate'),
          ),
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: _ActionButton(
            icon: Icons.auto_awesome_outlined,
            label: 'Atlas',
            onTap: () => context.go('/atlas'),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        decoration: BoxDecoration(
          color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: t.colorScheme.primary),
            const SizedBox(height: Space.s1),
            Text(
              label,
              style: t.textTheme.labelMedium?.copyWith(
                color: t.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
