import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';

/// Inbox screen — list of conversations (CLIN-07).
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  List<ConversationSummary> _conversations = [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
      if (session == null) return;

      final res = await http
          .get(
            Uri.parse('$apiBase/api/messages/conversations'),
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final raw = (body['conversations'] as List<dynamic>?) ?? [];
        setState(() {
          _conversations = raw
              .map(
                (e) => ConversationSummary.fromJson(e as Map<String, dynamic>),
              )
              .toList();
        });
      } else {
        setState(() => _error = 'Failed to load (${res.statusCode})');
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
      appBar: AppBar(title: const Text('Messages')),
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
            : _conversations.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: Neutrals.hint,
                      ),
                      const SizedBox(height: Space.s3),
                      Text(
                        'No messages yet.',
                        style: t.textTheme.titleSmall?.copyWith(
                          color: Neutrals.slate,
                        ),
                      ),
                      const SizedBox(height: Space.s1),
                      Text(
                        'When your care team sends you a message,\nit will appear here.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: Neutrals.hint,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s3,
                    vertical: Space.s2,
                  ),
                  itemCount: _conversations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = _conversations[i];
                    final name =
                        c.otherUser?['full_name'] as String? ?? 'Unknown';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: BrandColors.concordBlue.withValues(
                          alpha: 0.12,
                        ),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: BrandColors.concordBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: t.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (c.hasUnread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: BrandColors.concordBlue,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        c.lastMessage?['content'] as String? ?? 'No messages',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: c.hasUnread ? Neutrals.ink : Neutrals.slate,
                        ),
                      ),
                      trailing: c.lastMessage?['created_at'] != null
                          ? Text(
                              _formatDate(
                                c.lastMessage!['created_at'] as String,
                              ),
                              style: t.textTheme.labelSmall?.copyWith(
                                color: Neutrals.hint,
                              ),
                            )
                          : null,
                      onTap: () {
                        context.push('/messages/${c.id}');
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.parse(iso);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat.Hm().format(dt);
    }
    return DateFormat.MMMd().format(dt);
  }
}

class ConversationSummary {
  final String id;
  final Map<String, dynamic>? otherUser;
  final Map<String, dynamic>? lastMessage;
  final bool hasUnread;

  ConversationSummary({
    required this.id,
    this.otherUser,
    this.lastMessage,
    required this.hasUnread,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> j) {
    return ConversationSummary(
      id: j['id'] as String? ?? '',
      otherUser: j['other_user'] as Map<String, dynamic>?,
      lastMessage: j['last_message'] as Map<String, dynamic>?,
      hasUnread: j['has_unread'] as bool? ?? false,
    );
  }
}
