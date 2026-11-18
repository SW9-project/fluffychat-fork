// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/personalization/voice/language_pack.dart';
import 'package:fluffychat/personalization/voice/speech_transcriber.dart';
import 'package:fluffychat/personalization/voice/system_transcriber.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Stands in for the native plugin. Like the Android plugin, it sends the
/// `listening`, `notListening` and `done` statuses before the method call it
/// belongs to returns.
class FakeSpeechPlatform extends SpeechToTextPlatform {
  bool initResult = true;
  bool permission = true;

  /// When false, `listen` returns false without a status, as the plugin does
  /// when it still thinks the last session is listening.
  bool acceptListen = true;

  /// When set, `listen` throws it.
  PlatformException? listenError;

  final List<SpeechListenOptions?> listenCalls = [];
  int stopCalls = 0;
  int cancelCalls = 0;
  bool listening = false;
  bool _resultSent = false;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async => initResult;

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    listenCalls.add(options);
    final error = listenError;
    if (error != null) throw error;
    if (!acceptListen) return false;
    listening = true;
    _resultSent = false;
    onStatus?.call('listening');
    return true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _stopListening();
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _stopListening();
  }

  void _stopListening() {
    if (!listening) return;
    listening = false;
    onStatus?.call('notListening');
    onStatus?.call(_resultSent ? 'done' : 'doneNoResult');
  }

  /// The recogniser reports [words] for the current session.
  void hear(String words, {bool isFinal = false}) {
    _resultSent = true;
    onTextRecognition?.call(
      jsonEncode({
        'alternates': [
          {'recognizedWords': words, 'confidence': 0.9},
        ],
        'resultType': isFinal ? 2 : 0,
      }),
    );
  }

  /// The platform ends the session by itself after a pause: the final
  /// result, then the end-of-speech timer.
  void endSession(String words) {
    hear(words, isFinal: true);
    _stopListening();
  }

  /// The platform ends the session with [error], as on silence. The patched
  /// plugin sends the error before the statuses that end the session
  /// (packages/speech_to_text/PATCHES.md, change 5).
  void endWithError(String error) {
    onError?.call(jsonEncode({'errorMsg': error, 'permanent': true}));
    _stopListening();
  }

  int get onDeviceListenCalls =>
      listenCalls.where((o) => o?.onDevice == true).length;
}

/// Answers [states] one check after another, then repeats the last one.
class FakeLanguagePack implements LanguagePackService {
  final List<LanguagePackState> states;
  bool downloadStarts;
  int checks = 0;
  int downloads = 0;

  FakeLanguagePack(this.states, {this.downloadStarts = true});

  @override
  Future<LanguagePackState> check(String localeId) async =>
      states[checks++ < states.length ? checks - 1 : states.length - 1];

  @override
  Future<bool> download(String localeId) async {
    downloads++;
    return downloadStarts;
  }
}

void main() {
  late FakeSpeechPlatform platform;

  setUp(() {
    platform = FakeSpeechPlatform();
    SpeechToTextPlatform.instance = platform;
  });

  SystemTranscriber create({
    bool supported = true,
    LanguagePackService? pack,
  }) => SystemTranscriber(
    speech: SpeechToText.withMethodChannel(),
    isSupported: () async => supported,
    languagePack: pack,
    logStats: () => false,
  );

  Future<SystemTranscriber> recording(WidgetTester tester) async {
    final transcriber = create();
    await transcriber.start();
    await tester.pump();
    expect(transcriber.status.value, TranscriberStatus.recording);
    return transcriber;
  }

  /// Disposes [transcriber] and lets the plugin's own final-result timer run
  /// out, so no timer is left when the test ends.
  Future<void> finish(
    WidgetTester tester,
    SystemTranscriber transcriber,
  ) async {
    transcriber.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('unavailable when the device is not supported', (tester) async {
    final transcriber = create(supported: false);
    await transcriber.start();
    expect(transcriber.status.value, TranscriberStatus.unavailable);
    expect(platform.listenCalls, isEmpty);
    await finish(tester, transcriber);
  });

  testWidgets('every listen call is on-device only', (tester) async {
    final transcriber = await recording(tester);
    platform.endSession('turn on');
    await tester.pump();
    platform.endWithError('error_no_match');
    await tester.pump();
    platform.acceptListen = false;
    platform.endSession('dark mode');
    await tester.pump(SystemTranscriber.startTimeout);
    platform.acceptListen = true;
    await tester.pump(SystemTranscriber.retryDelay);
    expect(platform.listenCalls.length, 5);
    expect(platform.onDeviceListenCalls, platform.listenCalls.length);
    expect(platform.listenCalls.first?.localeId, 'en_US');
    expect(transcriber.status.value, TranscriberStatus.recording);
    await finish(tester, transcriber);
  });

  testWidgets('chains sessions the platform ends and joins their text', (
    tester,
  ) async {
    final transcriber = await recording(tester);
    platform.hear('make the');
    expect(transcriber.text.value, 'make the');
    platform.endSession('make the buttons');
    await tester.pump();
    expect(transcriber.status.value, TranscriberStatus.recording);
    expect(platform.listening, isTrue);
    platform.hear('bigger');
    expect(transcriber.text.value, 'make the buttons bigger');
    platform.endSession(' bigger please ');
    await tester.pump();
    expect(transcriber.text.value, 'make the buttons bigger please');
    expect(transcriber.status.value, TranscriberStatus.recording);

    final text = await transcriber.stop();
    expect(text, 'make the buttons bigger please');
    expect(transcriber.status.value, TranscriberStatus.ready);
    expect(transcriber.lastEnd, isNull);
    expect(transcriber.lastStats?.restarts, 2);
    expect(transcriber.lastStats?.gapsMs.length, 2);
    await finish(tester, transcriber);
  });

  testWidgets('no match and speech timeout start a new session', (
    tester,
  ) async {
    final transcriber = await recording(tester);
    platform.endWithError('error_speech_timeout');
    await tester.pump();
    platform.endWithError('error_no_match');
    await tester.pump();
    expect(transcriber.status.value, TranscriberStatus.recording);
    expect(platform.listening, isTrue);
    expect(platform.listenCalls.length, 3);
    platform.endSession('hello');
    await tester.pump();
    expect(transcriber.text.value, 'hello');
    await transcriber.stop();
    await finish(tester, transcriber);
  });

  testWidgets('chaining never calls stop on a finished session', (
    tester,
  ) async {
    // Android System Intelligence answers stop on a finished session with
    // ERROR_CLIENT, which then lands in the next session.
    final transcriber = await recording(tester);
    platform.endSession('one');
    await tester.pump();
    platform.endWithError('error_no_match');
    await tester.pump();
    platform.endSession('two');
    await tester.pump();
    expect(platform.listenCalls.length, 4);
    expect(platform.stopCalls, 0);
    await transcriber.stop();
    expect(platform.stopCalls, 1);
    await finish(tester, transcriber);
  });

  testWidgets('a new session is not cut short by partial results', (
    tester,
  ) async {
    final transcriber = await recording(tester);
    platform.endSession('first part');
    await tester.pump();
    expect(platform.listening, isTrue);
    // Partial results only, for longer than the plugin's final timeout.
    platform.hear('second');
    await tester.pump(const Duration(seconds: 3));
    platform.hear('second part');
    await tester.pump(const Duration(seconds: 3));
    expect(platform.listening, isTrue);
    expect(platform.listenCalls.length, 2);
    expect(transcriber.text.value, 'first part second part');
    final stopped = transcriber.stop();
    await tester.pump(const Duration(seconds: 3));
    expect(await stopped, 'first part second part');
    await finish(tester, transcriber);
  });

  testWidgets('nothing but the time limit stops a silent recording', (
    tester,
  ) async {
    final transcriber = await recording(tester);
    // 115 seconds of silence, one session ending every 5 seconds.
    for (var i = 0; i < 23; i++) {
      platform.endWithError('error_speech_timeout');
      await tester.pump(const Duration(seconds: 5));
      expect(transcriber.status.value, TranscriberStatus.recording);
    }
    platform.hear('still here');
    await tester.pump(const Duration(seconds: 4));
    expect(transcriber.status.value, TranscriberStatus.recording);
    await tester.pump(const Duration(seconds: 1));
    expect(transcriber.status.value, TranscriberStatus.finishing);
    await tester.pump(const Duration(seconds: 3));
    expect(transcriber.status.value, TranscriberStatus.ready);
    expect(transcriber.lastEnd, TranscriberEnd.timeLimit);
    expect(transcriber.text.value, 'still here');
    expect(transcriber.lastStats?.restarts, 23);
    await finish(tester, transcriber);
  });

  testWidgets('stop keeps the last partial result as final text', (
    tester,
  ) async {
    final transcriber = await recording(tester);
    platform.hear('turn off sounds');
    final stopped = transcriber.stop();
    await tester.pump();
    expect(transcriber.status.value, TranscriberStatus.finishing);
    await tester.pump(const Duration(seconds: 3));
    expect(await stopped, 'turn off sounds');
    expect(transcriber.status.value, TranscriberStatus.ready);
    await finish(tester, transcriber);
  });

  testWidgets('other errors stop the recording and keep the text', (
    tester,
  ) async {
    final transcriber = await recording(tester);
    platform.endSession('make it');
    await tester.pump();
    platform.hear('louder');
    platform.endWithError('error_audio_error');
    await tester.pump();
    expect(transcriber.status.value, TranscriberStatus.failed);
    expect(transcriber.lastEnd, TranscriberEnd.error);
    expect(transcriber.text.value, 'make it louder');
    expect(platform.listenCalls.length, 2);
    await finish(tester, transcriber);
  });

  testWidgets('a missing language pack hides voice input', (tester) async {
    final transcriber = await recording(tester);
    platform.endWithError('error_language_unavailable');
    await tester.pump();
    expect(transcriber.status.value, TranscriberStatus.unavailable);
    expect(transcriber.lastEnd, TranscriberEnd.languageMissing);
    await finish(tester, transcriber);
  });

  testWidgets('no on-device recognition hides voice input', (tester) async {
    platform.listenError = PlatformException(
      code: 'onDeviceUnavailable',
      message:
          'onDeviceUnavailable: on-device speech recognition is not '
          'available',
      details: 'onDeviceUnavailable',
    );
    final transcriber = create();
    await transcriber.start();
    await tester.pump();
    expect(transcriber.status.value, TranscriberStatus.unavailable);
    expect(transcriber.lastEnd, TranscriberEnd.notOnDevice);
    expect(platform.listenCalls.length, 1);
    await finish(tester, transcriber);
  });

  testWidgets('a denied permission fails without listening', (tester) async {
    platform
      ..initResult = false
      ..permission = false;
    final transcriber = create();
    await transcriber.start();
    expect(transcriber.status.value, TranscriberStatus.failed);
    expect(transcriber.lastEnd, TranscriberEnd.permissionDenied);
    expect(platform.listenCalls, isEmpty);
    await finish(tester, transcriber);
  });

  testWidgets('a failed restart is retried once, then stops', (tester) async {
    final transcriber = await recording(tester);
    platform.endSession('hello');
    await tester.pump();
    platform.acceptListen = false;
    platform.endSession('there');
    await tester.pump(SystemTranscriber.startTimeout);
    expect(transcriber.status.value, TranscriberStatus.recording);
    await tester.pump(SystemTranscriber.retryDelay);
    await tester.pump(SystemTranscriber.startTimeout);
    expect(transcriber.status.value, TranscriberStatus.failed);
    expect(transcriber.lastEnd, TranscriberEnd.restartFailed);
    expect(transcriber.text.value, 'hello there');
    expect(platform.listenCalls.length, 4);
    await finish(tester, transcriber);
  });

  testWidgets('cancel discards the text', (tester) async {
    final transcriber = await recording(tester);
    platform.hear('never mind');
    await transcriber.cancel();
    expect(transcriber.status.value, TranscriberStatus.ready);
    expect(transcriber.text.value, '');
    expect(platform.cancelCalls, 1);
    expect(platform.listening, isFalse);
    await finish(tester, transcriber);
  });

  group('language pack', () {
    Future<SystemTranscriber> opened(
      WidgetTester tester,
      FakeLanguagePack pack,
    ) async {
      final transcriber = create(pack: pack);
      await tester.pump();
      return transcriber;
    }

    testWidgets('an installed pack is not downloaded', (tester) async {
      final pack = FakeLanguagePack([LanguagePackState.installed]);
      final transcriber = await opened(tester, pack);
      expect(transcriber.status.value, TranscriberStatus.ready);
      expect(pack.downloads, 0);
      await finish(tester, transcriber);
    });

    testWidgets('a missing pack is downloaded when the tab opens', (
      tester,
    ) async {
      final pack = FakeLanguagePack([
        LanguagePackState.needsDownload,
        LanguagePackState.downloading,
        LanguagePackState.installed,
      ]);
      final transcriber = await opened(tester, pack);
      expect(pack.downloads, 1);
      expect(transcriber.status.value, TranscriberStatus.preparing);
      await transcriber.start();
      expect(platform.listenCalls, isEmpty);
      await tester.pump(SystemTranscriber.packCheckInterval);
      expect(transcriber.status.value, TranscriberStatus.preparing);
      await tester.pump(SystemTranscriber.packCheckInterval);
      expect(transcriber.status.value, TranscriberStatus.ready);
      expect(pack.downloads, 1);
      await finish(tester, transcriber);
    });

    testWidgets('a download that is not started offers the mic anyway', (
      tester,
    ) async {
      final pack = FakeLanguagePack([
        LanguagePackState.needsDownload,
      ], downloadStarts: false);
      final transcriber = await opened(tester, pack);
      expect(transcriber.status.value, TranscriberStatus.ready);
      await finish(tester, transcriber);
    });

    testWidgets('waiting for the pack ends after the limit', (tester) async {
      final pack = FakeLanguagePack([LanguagePackState.needsDownload]);
      final transcriber = await opened(tester, pack);
      expect(transcriber.status.value, TranscriberStatus.preparing);
      await tester.pump(
        SystemTranscriber.packWaitLimit - SystemTranscriber.packCheckInterval,
      );
      expect(transcriber.status.value, TranscriberStatus.preparing);
      await tester.pump(SystemTranscriber.packCheckInterval);
      expect(transcriber.status.value, TranscriberStatus.ready);
      expect(pack.downloads, 1);
      await finish(tester, transcriber);
    });

    testWidgets('an unsupported language hides the mic', (tester) async {
      final transcriber = await opened(
        tester,
        FakeLanguagePack([LanguagePackState.unsupported]),
      );
      expect(transcriber.status.value, TranscriberStatus.unavailable);
      await finish(tester, transcriber);
    });

    testWidgets('an unknown pack offers the mic', (tester) async {
      final transcriber = await opened(
        tester,
        FakeLanguagePack([LanguagePackState.unknown]),
      );
      expect(transcriber.status.value, TranscriberStatus.ready);
      await finish(tester, transcriber);
    });

    testWidgets('a recording that finds the pack missing downloads it', (
      tester,
    ) async {
      final pack = FakeLanguagePack([
        LanguagePackState.unknown,
        LanguagePackState.needsDownload,
        LanguagePackState.installed,
      ]);
      final transcriber = await opened(tester, pack);
      await transcriber.start();
      await tester.pump();
      platform.endWithError('error_language_unavailable');
      await tester.pump();
      expect(transcriber.lastEnd, TranscriberEnd.languageMissing);
      expect(transcriber.status.value, TranscriberStatus.preparing);
      expect(pack.downloads, 1);
      expect(platform.listenCalls.length, 1);
      await tester.pump(SystemTranscriber.packCheckInterval);
      expect(transcriber.status.value, TranscriberStatus.ready);
      await finish(tester, transcriber);
    });

    testWidgets('a pack that cannot be checked stays hidden after the error', (
      tester,
    ) async {
      final transcriber = await opened(
        tester,
        FakeLanguagePack([LanguagePackState.unknown]),
      );
      await transcriber.start();
      await tester.pump();
      platform.endWithError('error_language_unavailable');
      await tester.pump();
      expect(transcriber.status.value, TranscriberStatus.unavailable);
      await finish(tester, transcriber);
    });
  });

  testWidgets('dispose during a recording cancels the recogniser', (
    tester,
  ) async {
    final transcriber = await recording(tester);
    platform.hear('half a');
    await finish(tester, transcriber);
    await tester.pump();
    expect(platform.cancelCalls, 1);
    expect(platform.listening, isFalse);
  });
}
