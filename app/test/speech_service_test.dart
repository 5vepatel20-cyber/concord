// Tests for the pure transcript-merge helper used by SpeechService.
//
// The recognizer sends a stream of results. Partials grow over time:
//   "I'm feeling"
//   "I'm feeling tired"
//   "I'm feeling tired today"
//   → final "I'm feeling tired today"
//
// If we naively appended every partial, the field would show
// "I'm feeling I'm feeling tired I'm feeling tired today". The helper
// tracks the length of the previous partial and replaces that many
// characters at the end with the new one.

import 'package:flutter_test/flutter_test.dart';
import 'package:concord/core/voice/speech_service.dart';

void main() {
  group('appendTranscript', () {
    test('empty partial is a no-op', () {
      expect(
        appendTranscript(
          'hello',
          '',
          isFinal: false,
          hadFinalBefore: false,
          prevPartialLength: 0,
        ),
        'hello',
      );
      expect(
        appendTranscript(
          'hello',
          '',
          isFinal: true,
          hadFinalBefore: false,
          prevPartialLength: 5,
        ),
        'hello',
      );
    });

    test('first partial into empty notes has no leading space', () {
      expect(
        appendTranscript(
          '',
          'first words',
          isFinal: false,
          hadFinalBefore: false,
          prevPartialLength: 0,
        ),
        'first words',
      );
    });

    test('first partial appends with a space when notes is non-empty', () {
      expect(
        appendTranscript(
          'preceding text',
          'partial one',
          isFinal: false,
          hadFinalBefore: false,
          prevPartialLength: 0,
        ),
        'preceding text partial one',
      );
    });

    test('continuing partial replaces the trailing prevPartialLength', () {
      // After first partial, notes = "preceding text partial one".
      // Second partial of the same utterance: replace the last 12 chars.
      const afterFirst = 'preceding text partial one';
      expect(
        appendTranscript(
          afterFirst,
          'partial one two',
          isFinal: false,
          hadFinalBefore: false,
          prevPartialLength: 12,
        ),
        'preceding text partial one two',
      );
    });

    test('final strips the provisional and locks the final text', () {
      // Continuing partial that becomes final.
      const withProvisional = 'preceding text partial one two';
      expect(
        appendTranscript(
          withProvisional,
          'partial one two three',
          isFinal: true,
          hadFinalBefore: false,
          prevPartialLength: 16,
        ),
        'preceding text partial one two three',
      );
    });

    test('after a final, next partial appends a fresh segment', () {
      // First utterance fully locked in: "first sentence. " (length 16).
      // User pauses, then speaks again. Widget resets prevPartialLength
      // to 0; hadFinalBefore becomes true.
      const afterFirstFinal = 'first sentence. ';
      expect(
        appendTranscript(
          afterFirstFinal,
          'partial two',
          isFinal: false,
          hadFinalBefore: true,
          prevPartialLength: 0,
        ),
        'first sentence. partial two',
      );
    });

    test('continuing partial after a prior final still appends', () {
      // First segment finalized. Second utterance started. Now the
      // recognizer revises the second partial.
      const notes = 'first sentence. partial two';
      expect(
        appendTranscript(
          notes,
          'partial two three',
          isFinal: false,
          hadFinalBefore: true,
          prevPartialLength: 12,
        ),
        'first sentence. partial two three',
      );
    });

    test('does not introduce double spaces', () {
      // User finished a sentence ending with whitespace before pressing mic.
      const notes = 'I had nausea. ';
      expect(
        appendTranscript(
          notes,
          'today it is mild',
          isFinal: false,
          hadFinalBefore: true,
          prevPartialLength: 0,
        ),
        'I had nausea. today it is mild',
      );
    });

    test('recognizer reset (empty partial) is not destructive', () {
      // Some recognizers emit an empty final right at session start.
      const notes = 'existing notes';
      expect(
        appendTranscript(
          notes,
          '',
          isFinal: true,
          hadFinalBefore: false,
          prevPartialLength: 0,
        ),
        'existing notes',
      );
    });

    test('handles very long notes without dropping characters before cut', () {
      // The recognizer sends "I had nausea and it was quite bad today".
      // First partial was "I had nausea" (13 chars); second is
      // "I had nausea and it was" (23 chars); final is the full
      // sentence. We should see the full sentence, not chopped.
      const notesAfterFirst = 'preface. I had nausea';
      expect(
        appendTranscript(
          notesAfterFirst,
          'I had nausea and it was quite bad today',
          isFinal: true,
          hadFinalBefore: false,
          prevPartialLength: 13,
        ),
        'preface. I had nausea and it was quite bad today',
      );
    });

    test('partial shorter than prev still replaces cleanly', () {
      // Sometimes the recognizer backtracks. E.g. partial was "hello
      // world" but the recognizer realized it was "hello" — we should
      // still write the new partial verbatim at the cut position.
      const notes = 'start hello world';
      expect(
        appendTranscript(
          notes,
          'hello',
          isFinal: false,
          hadFinalBefore: false,
          prevPartialLength: 11,
        ),
        'start hello',
      );
    });
  });
}
