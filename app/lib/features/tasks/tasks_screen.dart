import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/result/result.dart';
import '../../data/models/task.dart';
import '../../data/repositories/task_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/severity_chip.dart';

final _tasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final repo = ref.read(taskRepositoryProvider);
  final result = await repo.fetchAll();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(_tasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(
              child: Text(
                'No tasks yet. Tap + to create one.',
                style: TextStyle(color: Neutrals.slate),
              ),
            );
          }
          final open = tasks.where((t) => !t.isDone).toList();
          final done = tasks.where((t) => t.isDone).toList();
          return ListView(
            padding: const EdgeInsets.all(Space.s4),
            children: [
              if (open.isNotEmpty) ...[
                Text(
                  'Open (${open.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: Space.s2),
                ...open.map((t) => _TaskTile(task: t, ref: ref)),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: Space.s6),
                Text(
                  'Completed (${done.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: Space.s2),
                ...done.map((t) => _TaskTile(task: t, ref: ref)),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String category = 'admin';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New task'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Task'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a task' : null,
              ),
              const SizedBox(height: Space.s3),
              DropdownButtonFormField<String>(
                value: category,
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('General')),
                  DropdownMenuItem(
                    value: 'appointment',
                    child: Text('Appointment'),
                  ),
                  DropdownMenuItem(
                    value: 'measurement',
                    child: Text('Measurement'),
                  ),
                  DropdownMenuItem(
                    value: 'lifestyle',
                    child: Text('Lifestyle'),
                  ),
                ],
                onChanged: (v) => category = v ?? 'admin',
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final repo = ref.read(taskRepositoryProvider);
              await repo.create(
                title: titleCtrl.text.trim(),
                category: category,
              );
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result == true && context.mounted) {
      ref.invalidate(_tasksProvider);
    }
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, required this.ref});
  final Task task;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final dueStr = task.dueAt != null
        ? DateFormat.MMMd().add_jm().format(task.dueAt!.toLocal())
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.s2),
      child: ListTile(
        leading: Icon(
          task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
          color: task.isDone ? SeverityColors.none : Neutrals.slate,
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.isDone ? TextDecoration.lineThrough : null,
            color: task.isDone ? Neutrals.slate : null,
          ),
        ),
        subtitle: Row(
          children: [
            if (dueStr != null) ...[
              Icon(Icons.schedule, size: 14, color: Neutrals.hint),
              const SizedBox(width: Space.s1),
              Text(dueStr, style: t.textTheme.bodySmall),
              const SizedBox(width: Space.s2),
            ],
            _CategoryChip(category: task.category),
          ],
        ),
        trailing: task.isDone
            ? null
            : IconButton(
                icon: Icon(Icons.check, color: SeverityColors.none),
                onPressed: () async {
                  final repo = ref.read(taskRepositoryProvider);
                  await repo.update(taskId: task.id, status: 'done');
                  ref.invalidate(_tasksProvider);
                },
              ),
        onTap: () => _showDetail(context, ref, task),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, Task task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Status', task.isDone ? 'Done' : 'Open'),
            _detailRow('Category', task.category),
            if (task.dueAt != null)
              _detailRow(
                'Due',
                DateFormat.yMMMd().add_jm().format(task.dueAt!),
              ),
            if (task.assignedTo != null)
              _detailRow('Assigned to', task.assignedTo!),
            _detailRow('Source', task.source),
          ],
        ),
        actions: [
          if (!task.isDone)
            TextButton(
              onPressed: () async {
                final repo = ref.read(taskRepositoryProvider);
                await repo.update(taskId: task.id, status: 'done');
                if (ctx.mounted) Navigator.of(ctx).pop();
                ref.invalidate(_tasksProvider);
              },
              child: const Text('Mark done'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s1),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});
  final String category;
  @override
  Widget build(BuildContext context) {
    final label = switch (category) {
      'appointment' => 'Appt',
      'measurement' => 'Measure',
      'lifestyle' => 'Lifestyle',
      _ => 'General',
    };
    return SeverityChip(grade: 0, size: SeverityChipSize.small);
  }
}
