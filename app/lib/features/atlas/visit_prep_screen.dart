import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class VisitPrepScreen extends ConsumerStatefulWidget {
  const VisitPrepScreen({super.key});

  @override
  ConsumerState<VisitPrepScreen> createState() => _VisitPrepScreenState();
}

class _VisitPrepScreenState extends ConsumerState<VisitPrepScreen> {
  Map<String, dynamic>? _prep;
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
      if (session == null) {
        setState(() => _error = 'Not signed in.');
        return;
      }
      final response = await http
          .post(
            Uri.parse('$apiBase/api/atlas/visit-prep'),
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 45));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() => _prep = body);
      } else {
        final msg =
            (jsonDecode(response.body) as Map<String, dynamic>)['error']
                as String? ??
            'Failed (${response.statusCode})';
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
        title: const Text('Visit Prep'),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Regenerate',
              onPressed: _load,
            ),
        ],
      ),
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
                        'Could not load visit prep',
                        style: t.textTheme.titleMedium,
                      ),
                      const SizedBox(height: Space.s2),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: Neutrals.slate,
                        ),
                      ),
                      const SizedBox(height: Space.s4),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _PrepBody(prep: _prep!, onRefresh: _load),
      ),
    );
  }
}

class _PrepBody extends StatelessWidget {
  const _PrepBody({required this.prep, required this.onRefresh});
  final Map<String, dynamic> prep;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final summary = prep['visit_summary'] as String? ?? '';
    final mention =
        (prep['mention_to_doctor'] as List<dynamic>?)?.cast<String>() ?? [];
    final questions =
        (prep['questions_to_ask'] as List<dynamic>?)?.cast<String>() ?? [];
    final medNotes = prep['medication_notes'] as String? ?? '';
    final trends = (prep['key_trends'] as List<dynamic>?)?.cast<String>() ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s3,
        Space.s5,
        Space.s10,
      ),
      children: [
        Row(
          children: [
            const Text('🤖', style: TextStyle(fontSize: 24)),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                'Your visit-prep summary is ready. Review it before your appointment.',
                style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s5),

        // Summary
        _Card(
          icon: Icons.summarize_outlined,
          title: 'Overview',
          child: Text(
            summary,
            style: t.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),

        // Trends
        if (trends.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          _Card(
            icon: Icons.trending_up,
            title: 'Key Trends',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: trends.map((t) => _BulletItem(text: t)).toList(),
            ),
          ),
        ],

        // Mention to doctor
        if (mention.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          _Card(
            icon: Icons.record_voice_over_outlined,
            title: 'Things to Mention',
            subtitle: 'Tell your doctor about these',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: mention.map((m) => _BulletItem(text: m)).toList(),
            ),
          ),
        ],

        // Questions
        if (questions.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          _Card(
            icon: Icons.help_outline,
            title: 'Questions to Ask',
            subtitle: 'Consider asking your care team',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: questions.map((q) => _BulletItem(text: q)).toList(),
            ),
          ),
        ],

        // Medication notes
        if (medNotes.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          _Card(
            icon: Icons.medication_outlined,
            title: 'Medication Notes',
            child: Text(
              medNotes,
              style: t.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],

        const SizedBox(height: Space.s5),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Regenerate'),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

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
                Icon(icon, color: BrandColors.concordBlue, size: 20),
                const SizedBox(width: Space.s2),
                Text(title, style: t.textTheme.titleSmall),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: Space.s1),
              Text(
                subtitle!,
                style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
              ),
            ],
            const SizedBox(height: Space.s3),
            child,
          ],
        ),
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: BrandColors.concordBlue,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(
              text,
              style: t.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
