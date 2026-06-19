// SSE (Server-Sent Events) client — hand-rolled for the Atlas chat endpoint.
//
// Frame grammar (matches the backend contract):
//   data: {"delta":"...", "done":false}\n\n
//   data: {"delta":"",   "done":true}\n\n
//   data: {"error":{"code":"...", "message":"..."}}\n\n
//
// Behavior:
//   - Each parsed event emits an `SseEvent` into the stream.
//   - Errors are emitted as SseEvent.error(...) and the stream closes.
//   - Caller is responsible for cancelling the subscription (returned by
//     http.Client.send) on widget dispose — iOS will hold the connection
//     open otherwise.

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:http/http.dart' as http;

sealed class SseEvent {
  const SseEvent();
}

class SseDelta extends SseEvent {
  const SseDelta(this.text);
  final String text;
}

class SseDone extends SseEvent {
  const SseDone();
}

class SseError extends SseEvent {
  const SseError({required this.code, required this.message});
  final String code;
  final String message;
}

class SseClient {
  SseClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// POST to [url] with a JSON [body] + bearer [token] and stream back
  /// SSE frames. [signal] cancels the whole request.
  Stream<SseEvent> postJsonStream({
    required Uri url,
    required Map<String, dynamic> body,
    required String token,
    CancelToken? signal,
  }) async* {
    final request = http.Request('POST', url)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer $token',
        'Connection': 'keep-alive',
      })
      ..body = jsonEncode(body);

    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final raw = await response.stream.bytesToString();
      yield SseError(
        code: 'http_${response.statusCode}',
        message: 'Atlas request failed: $raw',
      );
      return;
    }

    final buffer = StringBuffer();
    String? pendingEvent;
    final completer = Completer<void>();
    signal?.onCancel = () {
      if (!completer.isCompleted) completer.complete();
    };

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in lines) {
        if (signal?.isCancelled ?? false) return;
        if (line.isEmpty) {
          // Dispatch buffered event, if any.
          if (pendingEvent == 'data' && buffer.isNotEmpty) {
            final payload = buffer.toString();
            buffer.clear();
            pendingEvent = null;
            final ev = _parseData(payload);
            if (ev != null) yield ev;
            if (ev is SseDone) return;
          } else {
            pendingEvent = null;
            buffer.clear();
          }
          continue;
        }
        if (line.startsWith(':')) continue; // comment / heartbeat
        if (line.startsWith('event:')) {
          pendingEvent = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final chunk = line.substring(5).trim();
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(chunk);
          pendingEvent ??= 'data';
        }
        // ignore: unused_local_variable
        final _ = completer; // hold reference for the cancel hook above
      }
    } catch (e) {
      yield SseError(code: 'stream_error', message: e.toString());
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }

  SseEvent? _parseData(String payload) {
    try {
      final json = jsonDecode(payload);
      if (json is! Map) {
        return SseError(code: 'bad_frame', message: 'expected JSON object');
      }
      if (json['error'] is Map) {
        final err = json['error'] as Map;
        return SseError(
          code: err['code']?.toString() ?? 'unknown',
          message: err['message']?.toString() ?? 'Atlas error',
        );
      }
      final done = json['done'] == true;
      if (done) return const SseDone();
      final delta = json['delta'];
      if (delta is String && delta.isNotEmpty) return SseDelta(delta);
      return null;
    } catch (e) {
      return SseError(code: 'parse_error', message: e.toString());
    }
  }

  void close() => _client.close();
}

/// Simple cancel-token helper. Widgets that own a stream can hold one of
/// these and call [cancel] from dispose to tear down the http request.
class CancelToken {
  bool _cancelled = false;
  VoidCallback? _onCancel;

  bool get isCancelled => _cancelled;
  set onCancel(VoidCallback? cb) => _onCancel = cb;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}