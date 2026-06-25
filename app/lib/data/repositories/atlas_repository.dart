// Atlas chat repository — wraps the SSE client with auth + message list.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/sse_client.dart';
import '../supabase/supabase_provider.dart';

final sseClientProvider = Provider<SseClient>((ref) {
  final c = SseClient();
  ref.onDispose(c.close);
  return c;
});

final atlasRepositoryProvider = Provider<AtlasRepository>((ref) {
  return AtlasRepository(ref);
});

class ChatMessage {
  const ChatMessage._(this.role, this.text, this.streaming);
  final String role; // 'user' | 'assistant'
  final String text;
  final bool streaming;

  factory ChatMessage.user(String text) => ChatMessage._('user', text, false);
  factory ChatMessage.assistant(String text) =>
      ChatMessage._('assistant', text, false);
  factory ChatMessage.assistantStreaming(String text) =>
      ChatMessage._('assistant', text, true);
}

class AtlasRepository {
  AtlasRepository(this._ref);
  final Ref _ref;

  Stream<SseEvent> sendMessage({
    required List<ChatMessage> history,
    String? model,
    String? tone,
  }) {
    final supabase = _ref.read(supabaseClientProvider);
    final session = supabase.auth.currentSession;
    if (session == null) {
      throw StateError('Cannot chat with Atlas without an auth session');
    }
    final apiBase = _ref.read(apiBaseUrlProvider);
    return _ref
        .read(sseClientProvider)
        .postJsonStream(
          url: Uri.parse('$apiBase/api/atlas/chat'),
          body: {
            'messages': [
              for (final m in history) {'role': m.role, 'content': m.text},
            ],
            if (model != null) 'model': model,
            if (tone != null) 'tone': tone,
          },
          token: session.accessToken,
        );
  }
}
