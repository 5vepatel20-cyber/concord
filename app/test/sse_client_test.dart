// Tests for the SSE client frame parser.
//
// The parser is the core contract with the Atlas backend. We feed canned byte
// streams through a fake `http.Client` and assert the emitted SseEvent
// sequence. This is what makes the streaming chat work — getting it wrong
// silently breaks Atlas.

import 'dart:async';
import 'dart:convert';

import 'package:concord/core/network/sse_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Fake http.Client that yields a pre-canned stream of response bytes.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.body);
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = Stream<List<int>>.fromIterable([utf8.encode(body)]);
    return http.StreamedResponse(
      stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}

void main() {
  group('SseClient.postJsonStream', () {
    test('parses a single delta frame', () async {
      final client = _FakeClient('data: {"delta":"Hello"}\n\n');
      final sse = SseClient(client: client);
      final events = await sse
          .postJsonStream(
            url: Uri.parse('https://example.test/chat'),
            body: {'messages': []},
            token: 't',
          )
          .toList();
      expect(events.length, 1);
      expect(events.first, isA<SseDelta>());
      expect((events.first as SseDelta).text, 'Hello');
    });

    test('terminates on SseDone', () async {
      final client = _FakeClient(
        'data: {"delta":"a"}\n\n'
        'data: {"delta":"b"}\n\n'
        'data: {"done":true}\n\n',
      );
      final sse = SseClient(client: client);
      final events = await sse
          .postJsonStream(
            url: Uri.parse('https://example.test/chat'),
            body: const {},
            token: 't',
          )
          .toList();
      expect(events.length, 3);
      expect(events[0], isA<SseDelta>());
      expect((events[0] as SseDelta).text, 'a');
      expect(events[1], isA<SseDelta>());
      expect((events[1] as SseDelta).text, 'b');
      expect(events[2], isA<SseDone>());
    });

    test('emits SseError on error frame', () async {
      final client = _FakeClient(
        'data: {"error":{"code":"rate_limit","message":"slow down"}}\n\n',
      );
      final sse = SseClient(client: client);
      final events = await sse
          .postJsonStream(
            url: Uri.parse('https://example.test/chat'),
            body: const {},
            token: 't',
          )
          .toList();
      expect(events.length, 1);
      expect(events.first, isA<SseError>());
      final err = events.first as SseError;
      expect(err.code, 'rate_limit');
      expect(err.message, 'slow down');
    });

    test('emits SseError on non-2xx status', () async {
      final body = 'data: {"delta":"ignored"}';
      final stream = Stream<List<int>>.fromIterable([utf8.encode(body)]);
      final client = _StubClient(
        http.StreamedResponse(stream, 500, contentLength: body.length),
      );
      final sse = SseClient(client: client);
      final events = await sse
          .postJsonStream(
            url: Uri.parse('https://example.test/chat'),
            body: const {},
            token: 't',
          )
          .toList();
      expect(events.length, 1);
      expect(events.first, isA<SseError>());
      expect((events.first as SseError).code, 'http_500');
    });

    test('CancelToken stops the stream mid-flight', () async {
      // 3 frames; cancel before the third should drop it.
      final client = _FakeClient(
        'data: {"delta":"a"}\n\n'
        'data: {"delta":"b"}\n\n'
        'data: {"delta":"c"}\n\n',
      );
      final sse = SseClient(client: client);
      final cancel = CancelToken();
      final events = <SseEvent>[];
      final sub = sse
          .postJsonStream(
            url: Uri.parse('https://example.test/chat'),
            body: const {},
            token: 't',
            signal: cancel,
          )
          .listen((e) {
            events.add(e);
            if (events.length == 2) cancel.cancel();
          });
      // Pump microtasks so all bytes flow before we assert.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      // We should have at most the first two deltas.
      expect(events.length, lessThanOrEqualTo(2));
      expect(events.whereType<SseDelta>().map((e) => e.text), contains('a'));
    });

    test('ignores comment lines and blank data sections', () async {
      final client = _FakeClient(
        ': this is a heartbeat\n'
        'data: {"delta":"x"}\n\n'
        '\n'
        'data: {"done":true}\n\n',
      );
      final sse = SseClient(client: client);
      final events = await sse
          .postJsonStream(
            url: Uri.parse('https://example.test/chat'),
            body: const {},
            token: 't',
          )
          .toList();
      expect(events.length, 2);
      expect((events[0] as SseDelta).text, 'x');
      expect(events[1], isA<SseDone>());
    });
  });
}

class _StubClient extends http.BaseClient {
  _StubClient(this.response);
  final http.StreamedResponse response;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return response;
  }
}
