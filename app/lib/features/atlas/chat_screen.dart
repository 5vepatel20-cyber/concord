// Atlas chat screen — SSE-streamed assistant responses.
//
// UX:
//   - Send a message → optimistic user bubble appears immediately.
//   - An empty assistant bubble appears with a pulsing dot; tokens stream in.
//   - The scroll view auto-pins to the bottom as content grows.
//   - Disposing the widget cancels the open http request (iOS quirk).
//   - Tapping back during a stream cancels mid-flight.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/sse_client.dart';
import '../../data/repositories/atlas_repository.dart';
import '../../theme/tokens.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final List<ChatMessage> _messages = [
    ChatMessage.assistant(
      'Hi, I\'m Atlas. Ask me about your symptoms, your reports, or what to expect this week.',
    ),
  ];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;
  String _tone = 'default';
  CancelToken? _cancel;
  StreamSubscription<SseEvent>? _sub;

  @override
  void dispose() {
    _cancel?.cancel();
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sendText(String text) {
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _messages.add(ChatMessage.user(text));
      _messages.add(ChatMessage.assistantStreaming(''));
    });
    _scrollToBottom();
    _doSend();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _messages.add(ChatMessage.user(text));
      _messages.add(ChatMessage.assistantStreaming(''));
      _input.clear();
    });
    _scrollToBottom();
    _doSend();
  }

  void _doSend() {
    final cancel = CancelToken();
    _cancel = cancel;
    final stream = ref
        .read(atlasRepositoryProvider)
        .sendMessage(
          history: _messages.where((m) => !m.streaming).toList(growable: false),
          tone: _tone,
        );
    _sub = stream.listen(
      (ev) {
        switch (ev) {
          case SseDelta(:final text):
            setState(() {
              final i = _messages.length - 1;
              final cur = _messages[i];
              _messages[i] = ChatMessage.assistantStreaming(cur.text + text);
            });
            _scrollToBottom();
          case SseDone():
            setState(() {
              final i = _messages.length - 1;
              final cur = _messages[i];
              _messages[i] = ChatMessage.assistant(cur.text);
              _busy = false;
            });
          case SseError(:final message):
            setState(() {
              _error = message;
              _busy = false;
              // Drop the empty streaming bubble.
              if (_messages.isNotEmpty && _messages.last.streaming) {
                _messages.removeLast();
              }
            });
        }
      },
      onError: (Object e) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      },
      onDone: () {
        setState(() => _busy = false);
      },
      cancelOnError: true,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _cancelStream() {
    _cancel?.cancel();
    _sub?.cancel();
    _cancel = null;
    _sub = null;
    setState(() {
      _busy = false;
      if (_messages.isNotEmpty && _messages.last.streaming) {
        final cur = _messages.removeLast();
        if (cur.text.isNotEmpty) {
          _messages.add(ChatMessage.assistant(cur.text));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atlas'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'Response style',
            onSelected: (v) => setState(() => _tone = v),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'default',
                child: Text(
                  _tone == 'default' ? 'Default tone  ✓' : 'Default tone',
                ),
              ),
              PopupMenuItem(
                value: 'simple',
                child: Text(_tone == 'simple' ? 'Simple  ✓' : 'Simple'),
              ),
              PopupMenuItem(
                value: 'detailed',
                child: Text(_tone == 'detailed' ? 'Detailed  ✓' : 'Detailed'),
              ),
              PopupMenuItem(
                value: 'spanish',
                child: Text(_tone == 'spanish' ? 'Spanish  ✓' : 'Spanish'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.event_note_outlined),
            tooltip: 'Visit Prep',
            onPressed: () => context.push('/atlas/visit-prep'),
          ),
          if (_busy)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Stop',
              onPressed: _cancelStream,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(
                  Space.s4,
                  Space.s3,
                  Space.s4,
                  Space.s2,
                ),
                children: [
                  ..._messages.map((m) => _MessageBubble(message: m)),
                  if (_messages.length == 1)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s3),
                      child: _SuggestionChips(onTap: _sendText),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.s3),
                color: SeverityColors.severe.withValues(alpha: 0.08),
                child: Text(
                  _error!,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: SeverityColors.severe,
                  ),
                ),
              ),
            _Composer(controller: _input, busy: _busy, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isUser = message.role == 'user';
    final bg = isUser ? t.colorScheme.primaryContainer : Neutrals.surface;
    final fg = isUser
        ? t.colorScheme.onPrimaryContainer
        : t.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s3,
                vertical: Space.s2,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: isUser ? null : Border.all(color: Neutrals.mist),
              ),
              child: message.streaming && message.text.isEmpty
                  ? const _TypingDot()
                  : Text(
                      message.text,
                      style: t.textTheme.bodyMedium?.copyWith(color: fg),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  const _TypingDot();
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value - i * 0.15).clamp(0.0, 1.0);
            final opacity =
                0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Neutrals.slate,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s2,
        Space.s4,
        Space.s4,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Neutrals.mist)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask Atlas…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: Space.s2),
            FilledButton(
              onPressed: busy ? null : onSend,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prompt suggestions shown before the first user message.
class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({required this.onTap});
  final ValueChanged<String> onTap;

  static const _suggestions = [
    'How am I doing compared to last week?',
    'What should I ask my doctor?',
    'Prepare me for my next visit',
    'What does my symptom report show?',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.s1, bottom: Space.s2),
          child: Text(
            'Try asking',
            style: t.textTheme.labelMedium?.copyWith(color: Neutrals.slate),
          ),
        ),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s1,
          children: _suggestions
              .map(
                (s) => ActionChip(
                  label: Text(s, style: t.textTheme.bodySmall),
                  onPressed: () => onTap(s),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
