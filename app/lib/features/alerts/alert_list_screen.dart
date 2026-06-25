import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/alert_repository.dart';
import '../../theme/tokens.dart';

class AlertListScreen extends ConsumerWidget {
  const AlertListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final alertsAsync = ref.watch(alertListProvider);

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
              onRefresh: () => ref.refresh(alertListProvider.future),
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
                try {
                  await ref.read(alertRepositoryProvider).acknowledge(alert.id);
                  if (context.mounted) {
                    ref.refresh(alertListProvider.future);
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
