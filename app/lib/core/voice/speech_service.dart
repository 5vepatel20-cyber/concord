// SpeechService — SYM-05 voice input for free-text notes.
//
// Wraps the `speech_to_text` plugin behind a small, testable API. The plugin
// itself is stateful and hard to unit-test (real mic + OS recognizer), so
// this layer keeps the platform surface area in one place and pushes all
// merging/formatting logic into pure functions that the test suite can hit.
//
// Contract:
//   - The plugin uses the device's speech recognizer (SFSpeechRecognizer on
//     iOS, RecognitionService on Android). Audio is processed on-device when
//     the OS supports it; otherwise it's sent to the platform vendor's
//     cloud recognizer. We do not add our own network call.
//   - If the OS denies mic permission or speech isn't available, `init()`
//     returns false and the UI hides the mic button.
//   - The widget layer subscribes to `events` and writes into its
//     TextEditingController. The service does NOT hold a reference to any
//     controller — that's a Riverpod/state-management concern.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart' as sre;

/// Riverpod singleton. Shared by every screen that needs to dictate.
final speechServiceProvider = Provider<SpeechService>((ref) {
  return SpeechService._();
});

/// Events emitted by [SpeechService]. The widget layer pattern-matches on
/// these to decide whether to append partial text, finalize, or show an
/// error.
sealed class SpeechEvent {
  const SpeechEvent();
}

/// A live, partial transcript. The widget should REPLACE the in-progress
/// segment in its notes field with this — the recognizer sends a fresh
/// full transcript each tick, not a delta. The merging helper
/// [appendTranscript] handles this.
class SpeechPartial extends SpeechEvent {
  const SpeechPartial(this.text);
  final String text;
}

/// Final transcript for this utterance. The widget should commit the
/// text to its notes field (then start a new segment if the user keeps
/// dictating).
class SpeechFinal extends SpeechEvent {
  const SpeechFinal(this.text);
  final String text;
}

/// Recognition failed for some reason. [reason] is human-readable; suitable
/// for showing in a SnackBar.
class SpeechErrorEvent extends SpeechEvent {
  const SpeechErrorEvent(this.reason);
  final String reason;
}

/// Listening stopped without a final (user cancelled, OS killed the
/// session, etc). Widget should NOT modify the controller.
class SpeechStopped extends SpeechEvent {
  const SpeechStopped();
}

class SpeechService {
  SpeechService._();

  final stt.SpeechToText _plugin = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;

  final StreamController<SpeechEvent> _eventsCtrl =
      StreamController<SpeechEvent>.broadcast();

  /// Whether the OS reports speech recognition is available (locale +
  /// permission + service bound). Set after [init] succeeds.
  bool get isAvailable => _available;

  /// Whether we're currently listening. The widget binds its mic-button
  /// state to this.
  bool get isListening => _plugin.isListening;

  /// Stream of recognition events. Broadcast so multiple widgets (the
  /// notes field and a future summary card) can listen.
  Stream<SpeechEvent> get events => _eventsCtrl.stream;

  /// Best-effort init. Returns true if speech recognition is available
  /// on this device; false otherwise. Safe to call multiple times — only
  /// the first call does work.
  Future<bool> init() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _plugin.initialize(
        onError: (sre.SpeechRecognitionError err) {
          debugPrint('[voice] plugin error: ${err.errorMsg}');
          _eventsCtrl.add(SpeechErrorEvent(err.errorMsg));
        },
        onStatus: (status) {
          debugPrint('[voice] status: $status');
          // 'done' or 'notListening' both mean we've stopped.
          if (status == stt.SpeechToText.doneStatus ||
              status == stt.SpeechToText.notListeningStatus) {
            _eventsCtrl.add(const SpeechStopped());
          }
        },
      );
    } catch (e) {
      debugPrint('[voice] init threw: $e');
      _available = false;
    }
    return _available;
  }

  /// Whether the user has already granted RECORD_AUDIO / mic permission
  /// without prompting. Use before calling [startListening] if you want
  /// to show an "Allow microphone" hint first.
  Future<bool> hasPermission() async {
    if (!_initialized) await init();
    if (!_available) return false;
    try {
      return await _plugin.hasPermission;
    } catch (_) {
      // Older platform interface versions don't expose hasPermission; in
      // that case the OS will prompt on listen() and we can't pre-check.
      return true;
    }
  }

  /// Start listening. Partial transcripts stream as [SpeechPartial] events;
  /// when the OS finishes an utterance, [SpeechFinal] is emitted.
  ///
  /// [localeId] should be a BCP-47 tag like 'en_US'. If null, the OS picks
  /// the device's primary locale.
  ///
  /// Uses [ListenMode.dictation] (longer sentences) rather than the default
  /// 'confirmation' (short commands) since the patient is dictating notes.
  Future<void> startListening({String? localeId}) async {
    if (!_initialized) await init();
    if (!_available) {
      _eventsCtrl.add(
        const SpeechErrorEvent(
          "Speech recognition isn't available on this device",
        ),
      );
      return;
    }
    if (_plugin.isListening) return;
    try {
      await _plugin.listen(
        onResult: (result) {
          final words = result.recognizedWords;
          if (result.finalResult) {
            _eventsCtrl.add(SpeechFinal(words));
          } else {
            _eventsCtrl.add(SpeechPartial(words));
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          localeId: localeId,
        ),
      );
    } catch (e) {
      _eventsCtrl.add(SpeechErrorEvent("Couldn't start listening: $e"));
    }
  }

  /// Stop listening. The OS may emit a final result for the in-flight
  /// utterance; we don't synthesize one ourselves.
  Future<void> stop() async {
    if (!_plugin.isListening) return;
    try {
      await _plugin.stop();
    } catch (e) {
      debugPrint('[voice] stop threw: $e');
    }
  }

  /// Cancel without emitting a final result. Use when the user closes
  /// the sheet mid-utterance.
  Future<void> cancel() async {
    if (!_plugin.isListening) return;
    try {
      await _plugin.cancel();
    } catch (e) {
      debugPrint('[voice] cancel threw: $e');
    }
  }

  /// BCP-47 locale id matching the device's preferred locale for speech
  /// recognition (e.g. 'en_US'). Returns null if no installed locale is
  /// recognized — caller should fall back to letting the OS pick.
  Future<String?> pickDeviceLocaleId() async {
    if (!_initialized) await init();
    if (!_available) return null;
    try {
      final locales = await _plugin.locales();
      if (locales.isEmpty) return null;
      // The first locale is the system default; trust the OS ordering.
      return locales.first.localeId;
    } catch (e) {
      debugPrint('[voice] locales() threw: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    await _eventsCtrl.close();
  }
}

/// Pure helper: append a new [partial] transcript chunk to the existing
/// [notes] text. Kept outside the class so the test suite can hit it
/// without spinning up the plugin.
///
/// State the caller tracks (the widget does this in a stateful widget):
///   - [hadFinalBefore] — has the most recent utterance in this mic
///     session already been finalized? When true, a new partial belongs
///     to a fresh utterance and should be APPENDED, not replaced.
///   - [prevPartialLength] — the character count of the previous partial
///     currently appended to [notes]. When 0, no replacement happens.
///
/// Rules:
///   - Empty partial: no-op, return [notes] unchanged.
///   - First partial of a fresh utterance (prevPartialLength == 0):
///     append with a single space separator (if notes already has
///     content). Whether the partial is final or not doesn't change the
///     action — finalizing just means the recognizer is done with this
///     utterance, but the text we wrote is the same.
///   - Continuing partial of an in-progress utterance
///     (prevPartialLength > 0): replace the last [prevPartialLength]
///     characters of [notes] with the new partial. The recognizer's
///     partials grow monotonically as the user speaks, so cutting that
///     many chars off the end and pasting the new partial is safe.
///   - Final: lock the text in. With prevPartialLength > 0 we still
///     replace the provisional segment, but the widget will reset
///     prevPartialLength to 0 right after so the next utterance starts
///     fresh.
String appendTranscript(
  String notes,
  String partial, {
  required bool isFinal,
  required bool hadFinalBefore,
  required int prevPartialLength,
}) {
  final p = partial.trimLeft();
  if (p.isEmpty) return notes;

  // First partial of a fresh utterance: just append.
  if (prevPartialLength == 0) {
    return _joinWithSpace(notes, p);
  }

  // Continuing partial (or final) of an in-flight utterance: replace
  // the trailing [prevPartialLength] characters with the new partial.
  final cutAt = notes.length >= prevPartialLength
      ? notes.length - prevPartialLength
      : 0;
  final base = notes.substring(0, cutAt).trimRight();
  // `hadFinalBefore` is informational for the caller's state machine;
  // for the merge itself it doesn't change behavior — the previous
  // utterance was finalized and the next partial has prevPartialLength
  // == 0, which we already handled above.
  // ignore: unused_local_variable
  final _ = hadFinalBefore;
  return _joinWithSpace(base, p);
}

String _joinWithSpace(String left, String right) {
  if (right.isEmpty) return left;
  if (left.isEmpty) return right;
  // Avoid a double space if `left` already ends with whitespace.
  if (RegExp(r'\s$').hasMatch(left)) return '$left$right';
  return '$left $right';
}
