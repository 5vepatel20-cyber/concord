import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';

/// Message thread screen (CLIN-07). Shows messages and allows sending.
class MessageThreadScreen extends ConsumerStatefulWidget {
  const MessageThreadScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<MessageThreadScreen> createState() =>
      _MessageThreadScreenState();
}

class _MessageThreadScreenState extends ConsumerState<MessageThreadScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _userId;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages.isEmpty && _loading) {
      _load();
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
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
      _userId = session.user.id;

      final res = await http
          .get(
            Uri.parse(
              '$apiBase/api/messages/conversations/${widget.conversationId}',
            ),
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final raw = (body['messages'] as List<dynamic>?) ?? [];
        setState(() {
          _messages = raw
              .map((e) => Message.fromJson(e as Map<String, dynamic>))
              .toList();
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
        _markRead();
        _startPolling();
      } else {
        setState(() => _error = 'Failed to load (${res.statusCode})');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _pollForNewMessages();
    });
  }

  Future<void> _pollForNewMessages() async {
    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final latest = _messages.isNotEmpty
          ? _messages.last.createdAt.toIso8601String()
          : DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();

      final res = await http
          .get(
            Uri.parse(
              '$apiBase/api/messages/conversations/${widget.conversationId}'
              '?limit=20&before=$latest',
            ),
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted || res.statusCode != 200) return;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (body['messages'] as List<dynamic>?) ?? [];
      if (raw.isEmpty) return;

      final newMsgs = raw
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingIds = _messages.map((m) => m.id).toSet();
      final toAdd = newMsgs.where((m) => !existingIds.contains(m.id)).toList();

      if (toAdd.isNotEmpty) {
        setState(() {
          _messages.addAll(toAdd);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _markRead() async {
    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      await http.patch(
        Uri.parse(
          '$apiBase/api/messages/conversations/${widget.conversationId}',
        ),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _msgCtrl.text.trim();
    if (content.isEmpty) return;

    setState(() => _sending = true);
    _msgCtrl.clear();

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final res = await http
          .post(
            Uri.parse(
              '$apiBase/api/messages/conversations/${widget.conversationId}',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({'content': content}),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 201) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final msg = Message.fromJson(body['message'] as Map<String, dynamic>);
        setState(() => _messages.add(msg));
        _scrollToBottom();
      } else {
        _msgCtrl.text = content; // restore on failure
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to send')));
        }
      }
    } catch (e) {
      _msgCtrl.text = content;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation')),
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
            : Column(
                children: [
                  Expanded(
                    child: _messages.isEmpty
                        ? Center(
                            child: Text(
                              'No messages yet.',
                              style: t.textTheme.bodySmall?.copyWith(
                                color: Neutrals.hint,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(Space.s4),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final msg = _messages[i];
                              final isMe = msg.senderId == _userId;
                              return _MessageBubble(message: msg, isMe: isMe);
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(Space.s3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border(top: BorderSide(color: Neutrals.hairline)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Type a message…',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: Space.s3,
                                vertical: Space.s2,
                              ),
                            ),
                            maxLines: 3,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: Space.s2),
                        IconButton.filled(
                          onPressed: _sending ? null : _sendMessage,
                          icon: _sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe});
  final Message message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(Space.s3),
              decoration: BoxDecoration(
                color: isMe ? BrandColors.concordBlue : Neutrals.mist,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(Radii.md),
                  topRight: const Radius.circular(Radii.md),
                  bottomLeft: isMe
                      ? const Radius.circular(Radii.md)
                      : const Radius.circular(Radii.sm),
                  bottomRight: isMe
                      ? const Radius.circular(Radii.sm)
                      : const Radius.circular(Radii.md),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(color: isMe ? Colors.white : Neutrals.ink),
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    DateFormat.Hm().format(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.7)
                          : Neutrals.hint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Message {
  final String id;
  final String senderId;
  final String content;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> j) {
    return Message(
      id: j['id'] as String? ?? '',
      senderId: j['sender_id'] as String? ?? '',
      content: j['content'] as String? ?? '',
      createdAt: DateTime.parse(j['created_at'] as String? ?? ''),
    );
  }
}
