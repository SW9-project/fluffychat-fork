// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

enum TranscriberStatus {
  /// This device cannot recognise speech on the device. The mic is hidden.
  unavailable,

  /// Ready to record.
  ready,

  /// Recording. Stays here across the recogniser's own session restarts.
  recording,

  /// The user tapped stop and the final text is on its way.
  finishing,

  /// The last recording ended with an error. See
  /// [SpeechTranscriber.lastEnd]. [SpeechTranscriber.start] may be tried
  /// again.
  failed,
}

/// Why a recording ended without the user tapping stop.
enum TranscriberEnd {
  /// The safety cap was reached. The text so far is kept, as after stop.
  timeLimit,

  /// The user did not allow the microphone or speech recognition.
  permissionDenied,

  /// The device cannot recognise speech on the device at all.
  notOnDevice,

  /// On-device recognition exists, but the language pack is missing.
  languageMissing,

  /// The recogniser could not be restarted after a session ended.
  restartFailed,

  /// Any other recogniser error.
  error,
}

/// Turns the user's speech into text for the Assist prompt field. The rest of
/// the app only knows this interface, so the engine can be swapped.
///
/// Everything runs on the device: no implementation may send audio or text
/// over the network. Only the user's taps start and stop a recording; a
/// pause in speech never ends it.
abstract class SpeechTranscriber {
  ValueListenable<TranscriberStatus> get status;

  /// Joined text so far, including the live partial result.
  ValueListenable<String> get text;

  /// Why the last recording ended by itself, or null when the user stopped
  /// or cancelled it. Reset by [start].
  TranscriberEnd? get lastEnd;

  /// Starts recording (the user tapped record on).
  Future<void> start();

  /// Ends recording (the user tapped record off) and returns the final text.
  Future<String> stop();

  /// Ends recording and discards the text.
  Future<void> cancel();

  void dispose();
}
