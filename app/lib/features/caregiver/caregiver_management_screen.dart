import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/caregiver_repository.dart';
import '../../theme/tokens.dart';

class CaregiverManagementScreen extends ConsumerStatefulWidget {
  const CaregiverManagementScreen({super.key});

  @override
  ConsumerState<CaregiverManagementScreen> createState() =>
      _CaregiverManagementScreenState();
}

class _CaregiverManagementScreenState
    extends ConsumerState<CaregiverManagementScreen> {
  List<Map<String, dynamic>> _caregivers = [];
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
      final data = await ref.read(caregiverRepositoryProvider).list();
      setState(() {
        _caregivers = List<Map<String, dynamic>>.from(
          data['as_patient'] as List<dynamic>,
        );
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showInviteDialog() async {
    final emailCtrl = TextEditingController();
    String relationship = 'friend';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Invite caregiver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'caregiver@example.com',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: Space.s3),
              DropdownButtonFormField<String>(
                value: relationship,
                decoration: const InputDecoration(labelText: 'Relationship'),
                items: const [
                  DropdownMenuItem(value: 'spouse', child: Text('Spouse')),
                  DropdownMenuItem(value: 'child', child: Text('Child')),
                  DropdownMenuItem(value: 'parent', child: Text('Parent')),
                  DropdownMenuItem(value: 'friend', child: Text('Friend')),
                  DropdownMenuItem(
                    value: 'clinician',
                    child: Text('Clinician'),
                  ),
                  DropdownMenuItem(
                    value: 'care_navigator',
                    child: Text('Care navigator'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => relationship = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop({
                'email': emailCtrl.text.trim(),
                'relationship': relationship,
              }),
              child: const Text('Send invite'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    final email = result['email']!;
    final rel = result['relationship']!;
    if (email.isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(caregiverRepositoryProvider)
          .invite(email: email, relationship: rel);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invite sent to $email')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: SeverityColors.severe,
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmRevoke(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove caregiver'),
        content: Text(
          'Remove $name from your care team? They will no longer receive alerts or be able to view your data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SeverityColors.severe,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(caregiverRepositoryProvider).revoke(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Caregiver removed')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: SeverityColors.severe,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Care team'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Invite caregiver',
            onPressed: _showInviteDialog,
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
            : _caregivers.isEmpty
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
                      Text(
                        'Your care team is empty',
                        style: t.textTheme.titleMedium,
                      ),
                      const SizedBox(height: Space.s2),
                      Text(
                        'Invite family or friends to help track your progress and receive alerts.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: Neutrals.slate,
                        ),
                      ),
                      const SizedBox(height: Space.s4),
                      FilledButton.icon(
                        onPressed: _showInviteDialog,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Invite caregiver'),
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
                      'Your caregivers',
                      style: t.textTheme.titleSmall?.copyWith(
                        color: Neutrals.slate,
                      ),
                    ),
                    const SizedBox(height: Space.s2),
                    ..._caregivers.map(
                      (c) => _CaregiverTile(
                        caregiver: c,
                        onRevoke: () => _confirmRevoke(
                          c['id'] as String,
                          (c['member'] as Map<String, dynamic>?)?['email']
                                  as String? ??
                              'Unknown',
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

class _CaregiverTile extends StatelessWidget {
  const _CaregiverTile({required this.caregiver, required this.onRevoke});
  final Map<String, dynamic> caregiver;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final member = caregiver['member'] as Map<String, dynamic>?;
    final email = member?['email'] as String? ?? 'Unknown';
    final name = member?['full_name'] as String?;
    final relationship = caregiver['relationship'] as String? ?? '';
    final status = caregiver['status'] as String? ?? 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: Space.s2),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: BrandColors.concordBlueTint,
          child: Icon(Icons.person, color: BrandColors.concordBlue),
        ),
        title: Text(name ?? email, style: t.textTheme.titleSmall),
        subtitle: Text(
          '${_relationshipLabel(relationship)} · ${_statusLabel(status)}',
          style: t.textTheme.bodySmall?.copyWith(color: Neutrals.slate),
        ),
        trailing: status == 'active'
            ? IconButton(
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: SeverityColors.severe,
                ),
                tooltip: 'Remove',
                onPressed: onRevoke,
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

  String _statusLabel(String s) {
    switch (s) {
      case 'active':
        return 'Active';
      case 'pending':
        return 'Pending';
      case 'revoked':
        return 'Revoked';
      default:
        return s;
    }
  }
}
