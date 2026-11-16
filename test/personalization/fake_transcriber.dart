// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/personalization/voice/speech_transcriber.dart';
import 'package:flutter/foundation.dart';

/// [SpeechTranscriber] for widget tests. Each method below acts like the
/// recogniser or the platform, so a test can play a whole recording.
class FakeTranscriber implements SpeechTranscriber {
  final ValueNotifier<TranscriberStatus> _status;
  final ValueNotifier<String> _text = ValueNotifier('');
  final List<String> _committed = [];
  String _partial = '';

  @override
  TranscriberEnd? lastEnd;

  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  /// Recogniser sessions in the current recording, the first included.
  int sessions = 0;
  bool disposed = false;

  /// When set, [stop] stays in [TranscriberStatus.finishing] until
  /// [completeStop] is called.
  bool holdStop = false;
  Completer<void>? _stopGate;

  FakeTranscriber({TranscriberStatus status = TranscriberStatus.ready})
    : _status = ValueNotifier(status);

  @override
  ValueListenable<TranscriberStatus> get status => _status;

  @override
  ValueListenable<String> get text => _text;

  set statusValue(TranscriberStatus status) => _status.value = status;

  void _publish() => _text.value = [
    ..._committed,
    if (_partial.isNotEmpty) _partial,
  ].join(' ');

  /// The recogniser heard [words] so far in the current session.
  void hear(String words) {
    _partial = words.trim();
    _publish();
  }

  /// The platform ended the session by itself, as after a pause, a timeout
  /// or a "no match". The recording goes on in a new session.
  void endSession() {
    if (_partial.isNotEmpty) _committed.add(_partial);
    _partial = '';
    sessions++;
    _publish();
  }

  /// The recording stopped with an error, as [SystemTranscriber] does.
  void fail(TranscriberEnd end, {bool unavailable = false}) {
    lastEnd = end;
    _commitPartial();
    _status.value = unavailable
        ? TranscriberStatus.unavailable
        : TranscriberStatus.failed;
  }

  /// The recording reached its time limit and stopped like after stop.
  void reachTimeLimit() {
    lastEnd = TranscriberEnd.timeLimit;
    _commitPartial();
    _status.value = TranscriberStatus.ready;
  }

  void _commitPartial() {
    if (_partial.isNotEmpty) _committed.add(_partial);
    _partial = '';
    _publish();
  }

  /// Lets a [stop] held by [holdStop] finish.
  void completeStop() => _stopGate?.complete();

  @override
  Future<void> start() async {
    startCalls++;
    if (_status.value != TranscriberStatus.ready &&
        _status.value != TranscriberStatus.failed) {
      return;
    }
    lastEnd = null;
    _committed.clear();
    _partial = '';
    sessions = 1;
    _publish();
    _status.value = TranscriberStatus.recording;
  }

  @override
  Future<String> stop() async {
    stopCalls++;
    if (_status.value != TranscriberStatus.recording) return _text.value;
    _status.value = TranscriberStatus.finishing;
    if (holdStop) {
      final gate = _stopGate = Completer<void>();
      await gate.future;
      _stopGate = null;
    }
    _commitPartial();
    _status.value = TranscriberStatus.ready;
    return _text.value;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _committed.clear();
    _partial = '';
    _publish();
    if (_status.value == TranscriberStatus.recording ||
        _status.value == TranscriberStatus.finishing) {
      _status.value = TranscriberStatus.ready;
    }
  }

  @override
  void dispose() {
    disposed = true;
  }
}
