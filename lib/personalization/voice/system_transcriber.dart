// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart'
    show SpeechToTextPlatform;

import 'language_pack.dart';
import 'speech_transcriber.dart';

/// What one recording looked like underneath, for judging whether the
/// recogniser restarts are acceptable. Goes to the debug log only, never to
/// the study log, and never contains audio or text.
@immutable
class RecordingStats {
  final int durationMs;

  /// How often a new recogniser session was started after one ended by
  /// itself.
  final int restarts;

  /// For each restart: milliseconds from the end of a session to the next
  /// session listening.
  final List<int> gapsMs;

  /// Why the recording ended, or null when the user stopped or cancelled it.
  final TranscriberEnd? end;

  const RecordingStats({
    required this.durationMs,
    required this.restarts,
    required this.gapsMs,
    this.end,
  });

  @override
  String toString() =>
      'duration_ms=$durationMs restarts=$restarts gaps_ms=$gapsMs '
      'end=${end?.name ?? 'user'}';
}

enum _SessionState {
  /// No recogniser session.
  idle,

  /// `listen` was called, waiting for the `listening` status.
  starting,

  /// The recogniser is listening.
  listening,

  /// The recogniser stopped listening, waiting for the session's final
  /// result.
  ending,
}

/// [SpeechTranscriber] backed by the phone's own recogniser through the
/// patched speech_to_text plugin (`packages/speech_to_text`), in on-device
/// mode only. Every `listen` call passes `onDevice: true`, and the patched
/// plugin fails instead of falling back to a recogniser that may use the
/// network.
///
/// Android ends a recogniser session after a short pause, and that cannot be
/// turned off. This class chains sessions: until the user taps stop, every
/// session that ends by itself is followed at once by a new one, and their
/// texts are joined with one space. The user sees one recording.
///
/// Only Android 12 (API 31) and later with an on-device recognition service
/// is supported. iOS is off until it is decided whether the study needs it.
///
/// Each time it is created (when the Assist tab opens), it checks the
/// language pack and asks the system to download it when it is missing. The
/// status is [TranscriberStatus.preparing] until the pack is there.
class SystemTranscriber implements SpeechTranscriber {
  /// A recording stops by itself after this long. This guards against a
  /// forgotten open microphone, not against pauses.
  static const maxRecording = Duration(minutes: 2);

  /// A session that fails to start is retried once after this delay.
  static const retryDelay = Duration(milliseconds: 300);

  /// How long a new session may take to report that it is listening.
  static const startTimeout = Duration(seconds: 1);

  /// How long to wait for a session's final result after it stopped
  /// listening. After that its last partial result is used.
  static const finalResultTimeout = Duration(milliseconds: 2500);

  /// How often the language pack is checked while it downloads.
  static const packCheckInterval = Duration(seconds: 5);

  /// After this long without the pack, the mic is offered anyway, and a
  /// recording explains what is missing.
  static const packWaitLimit = Duration(minutes: 15);

  /// Errors that only mean the session ended without (more) speech.
  static const _sessionEndErrors = {'error_no_match', 'error_speech_timeout'};

  /// Errors that mean a session could not start. Retried once.
  static const _startErrors = {
    'error_busy',
    'error_client',
    'error_recognizer_unavailable',
    'error_server_disconnected',
    'error_too_many_requests',
  };

  /// Errors of the on-device recogniser when the language pack is missing.
  static const _languageErrors = {
    'error_language_not_supported',
    'error_language_unavailable',
  };

  static const _permissionErrors = {'error_permission'};

  /// Marker in the patched plugin's error when on-device recognition is not
  /// available.
  static const _onDeviceUnavailable = 'onDeviceUnavailable';

  /// The recognition language, such as `en_US`.
  final String localeId;

  final SpeechToText _speech;
  final LanguagePackService? _languagePack;
  final bool Function() _logStats;

  final ValueNotifier<TranscriberStatus> _status = ValueNotifier(
    TranscriberStatus.unavailable,
  );
  final ValueNotifier<String> _text = ValueNotifier('');

  /// Completes once the initial status is known.
  late final Future<void> _availability;
  bool _disposed = false;
  TranscriberEnd? _lastEnd;
  RecordingStats? _lastStats;

  // The language pack.
  bool _downloadRequested = false;

  /// Checks made while waiting for the pack.
  int _packWaits = 0;
  Timer? _packTimer;

  // One recording.
  bool _initializing = false;
  bool _userWantsRecording = false;
  final List<String> _committed = [];
  Timer? _capTimer;
  Completer<void>? _finished;
  Stopwatch _clock = Stopwatch();
  int _restarts = 0;
  final List<int> _gapsMs = [];
  int? _sessionEndedAtMs;

  // The current recogniser session.
  int _session = 0;
  _SessionState _sessionState = _SessionState.idle;
  String _sessionText = '';
  bool _retried = false;
  Timer? _startTimer;
  Timer? _finalTimer;
  Timer? _retryTimer;

  /// [speech], [isSupported], [languagePack] and [logStats] are for tests.
  /// Without [languagePack], Android uses [AndroidLanguagePack] and other
  /// platforms check no pack.
  SystemTranscriber({
    this.localeId = 'en_US',
    SpeechToText? speech,
    Future<bool> Function()? isSupported,
    LanguagePackService? languagePack,
    bool Function()? logStats,
  }) : _speech = speech ?? SpeechToText(),
       _languagePack =
           languagePack ??
           (PlatformInfos.isAndroid ? const AndroidLanguagePack() : null),
       _logStats = logStats ?? _defaultLogStats {
    _availability = _checkAvailability(
      isSupported ?? SystemTranscriber.isSupported,
    );
  }

  @override
  ValueListenable<TranscriberStatus> get status => _status;

  @override
  ValueListenable<String> get text => _text;

  @override
  TranscriberEnd? get lastEnd => _lastEnd;

  /// Restart counts and gaps of the last finished recording.
  RecordingStats? get lastStats => _lastStats;

  /// Android 12 or later, with an on-device recognition service. Asks for no
  /// permission. The language pack is checked separately.
  static Future<bool> isSupported() async {
    if (!PlatformInfos.isAndroid) return false;
    final info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt < 31) return false;
    return SpeechToTextPlatform.instance.hasOnDeviceSupport();
  }

  static bool _defaultLogStats() {
    if (kDebugMode) return true;
    try {
      return StudySettings.instance.value.logging;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkAvailability(Future<bool> Function() check) async {
    try {
      if (!await check()) return;
    } catch (e, s) {
      Logs().w('Voice input unavailable', e, s);
      return;
    }
    await _preparePack();
  }

  /// Checks the language pack, asks the system to download it when it is
  /// missing, and checks again every [packCheckInterval] until it is there.
  ///
  /// After a recording found the pack missing ([afterLanguageError]), a pack
  /// that cannot be downloaded keeps the mic hidden instead of offering it
  /// again.
  Future<void> _preparePack({bool afterLanguageError = false}) async {
    _packTimer?.cancel();
    final pack = _languagePack;
    final fallback = afterLanguageError
        ? TranscriberStatus.unavailable
        : TranscriberStatus.ready;
    if (pack == null) {
      _setPackStatus(fallback);
      return;
    }
    var state = await _checkPack(pack);
    if (_disposed) return;
    if (state == LanguagePackState.needsDownload && !_downloadRequested) {
      _downloadRequested = true;
      _packWaits = 0;
      bool started;
      try {
        started = await pack.download(localeId);
      } catch (e, s) {
        Logs().w('Voice input: language pack download failed', e, s);
        started = false;
      }
      if (_disposed) return;
      // Without a download, the first recording explains what is missing.
      if (!started) {
        _setPackStatus(fallback);
        return;
      }
      state = LanguagePackState.downloading;
    }
    switch (state) {
      case LanguagePackState.installed:
        _setPackStatus(TranscriberStatus.ready);
      case LanguagePackState.unknown:
        _setPackStatus(fallback);
      case LanguagePackState.unsupported:
        _setPackStatus(TranscriberStatus.unavailable);
      case LanguagePackState.downloading || LanguagePackState.needsDownload:
        if (packCheckInterval * _packWaits++ >= packWaitLimit) {
          _setPackStatus(fallback);
          return;
        }
        _setPackStatus(TranscriberStatus.preparing);
        _packTimer = Timer(
          packCheckInterval,
          () => _preparePack(afterLanguageError: afterLanguageError),
        );
    }
  }

  Future<LanguagePackState> _checkPack(LanguagePackService pack) async {
    try {
      return await pack.check(localeId);
    } catch (e, s) {
      Logs().w('Voice input: language pack check failed', e, s);
      return LanguagePackState.unknown;
    }
  }

  /// A pack result never interrupts a recording.
  void _setPackStatus(TranscriberStatus status) {
    if (_inRecording || _initializing) return;
    _setStatus(status);
  }

  void _setStatus(TranscriberStatus status) {
    if (!_disposed) _status.value = status;
  }

  void _publish() {
    if (_disposed) return;
    _text.value = [
      ..._committed,
      if (_sessionText.isNotEmpty) _sessionText,
    ].join(' ');
  }

  bool get _inRecording =>
      _status.value == TranscriberStatus.recording ||
      _status.value == TranscriberStatus.finishing;

  int get _now => _clock.elapsedMilliseconds;

  /// The options of every `listen` call.
  ///
  /// `listenFor` and `pauseFor` stay unset. Unset, the plugin never ends a
  /// session by its own timers, so sessions last as long as the platform
  /// allows. On Android `pauseFor` also delays the plugin's end-of-session
  /// status after the end of speech, so a long value would delay every
  /// restart.
  @visibleForTesting
  SpeechListenOptions get listenOptions => SpeechListenOptions(
    onDevice: true,
    listenMode: ListenMode.dictation,
    partialResults: true,
    cancelOnError: false,
    localeId: localeId,
  );

  @override
  Future<void> start() async {
    await _availability;
    if (_disposed || _initializing) return;
    final status = _status.value;
    if (status == TranscriberStatus.unavailable ||
        status == TranscriberStatus.preparing ||
        _inRecording) {
      return;
    }

    _lastEnd = null;
    _committed.clear();
    _sessionText = '';
    _publish();
    _restarts = 0;
    _gapsMs.clear();
    _sessionEndedAtMs = null;
    _retried = false;
    _userWantsRecording = true;

    // Asks for the microphone permission on first use.
    _initializing = true;
    bool initialized;
    try {
      initialized = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
    } catch (e, s) {
      Logs().w('Voice input: initialize failed', e, s);
      initialized = false;
    } finally {
      _initializing = false;
    }
    if (_disposed || !_userWantsRecording) return;
    // The plugin is shared, and only its first initialize sets listeners.
    _speech.statusListener = _onStatus;
    _speech.errorListener = _onError;
    if (!initialized) {
      final permitted = await _speech.hasPermission.catchError((_) => false);
      if (_disposed || !_userWantsRecording) return;
      _fail(permitted ? TranscriberEnd.error : TranscriberEnd.permissionDenied);
      return;
    }

    _clock = Stopwatch()..start();
    _setStatus(TranscriberStatus.recording);
    _capTimer = Timer(maxRecording, _onTimeLimit);
    await _startSession(chained: false);
  }

  Future<void> _startSession({required bool chained}) async {
    final session = ++_session;
    _sessionState = _SessionState.starting;
    _sessionText = '';
    _finalTimer?.cancel();
    _finalTimer = null;
    if (chained) _restarts++;
    try {
      await _speech.listen(
        onResult: (result) => _onResult(session, result),
        listenOptions: listenOptions,
      );
    } on ListenFailedException catch (e) {
      if (session != _session || _disposed) return;
      if ('${e.message} ${e.details}'.contains(_onDeviceUnavailable)) {
        _fail(TranscriberEnd.notOnDevice, unavailable: true);
        return;
      }
      Logs().w('Voice input: listen failed: ${e.message}');
      _retryOrFail();
      return;
    } catch (e, s) {
      if (session != _session || _disposed) return;
      Logs().w('Voice input: listen failed', e, s);
      _retryOrFail();
      return;
    }
    if (session != _session || _disposed) return;
    if (_sessionState == _SessionState.starting) {
      // The plugin refuses a listen call silently, for example while it
      // still thinks the last session is listening.
      _startTimer = Timer(startTimeout, () {
        if (session == _session && _sessionState == _SessionState.starting) {
          Logs().w('Voice input: session did not start');
          _retryOrFail();
        }
      });
    }
  }

  void _retryOrFail() {
    _startTimer?.cancel();
    _finalTimer?.cancel();
    _finalTimer = null;
    _sessionState = _SessionState.idle;
    if (!_userWantsRecording) return;
    if (_retried) {
      _fail(TranscriberEnd.restartFailed);
      return;
    }
    _retried = true;
    _retryTimer = Timer(retryDelay, () {
      if (_disposed || !_userWantsRecording) return;
      _startSession(chained: false);
    });
  }

  void _onResult(int session, SpeechRecognitionResult result) {
    if (_disposed || session != _session || !_inRecording) return;
    if (_sessionState == _SessionState.idle) return;
    _sessionText = result.recognizedWords.trim();
    _publish();
    if (!result.finalResult) return;
    // A session that delivered its result works: a later start failure gets
    // its own retry.
    _retried = false;
    if (_status.value == TranscriberStatus.finishing ||
        _sessionState == _SessionState.ending) {
      _endSession();
      return;
    }
    // The final result ends the session. The patched plugin follows it at
    // once with `notListening` and `done`, which start the next session
    // (PATCHES.md, change 6). Never call `stop` here: on a finished session
    // the recognition service answers with ERROR_CLIENT, which then arrives
    // during the next session.
    _markSessionEnding();
    _finalTimer ??= Timer(finalResultTimeout, _endSession);
  }

  void _onStatus(String status) {
    if (_disposed || !_inRecording) return;
    switch (status) {
      case SpeechToText.listeningStatus:
        if (_sessionState != _SessionState.starting) return;
        _startTimer?.cancel();
        _sessionState = _SessionState.listening;
        final endedAt = _sessionEndedAtMs;
        if (endedAt != null) {
          _gapsMs.add(_now - endedAt);
          _sessionEndedAtMs = null;
        }
      case SpeechToText.notListeningStatus:
        // Before `listening`, this belongs to the session before.
        if (_sessionState != _SessionState.listening) return;
        _markSessionEnding();
        _finalTimer ??= Timer(finalResultTimeout, _endSession);
      case SpeechToText.doneStatus:
        if (_sessionState != _SessionState.listening &&
            _sessionState != _SessionState.ending) {
          return;
        }
        _endSession();
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (_disposed || !_inRecording) return;
    final message = error.errorMsg;
    Logs().d('Voice input: recogniser error $message');
    if (_status.value == TranscriberStatus.finishing) {
      // The user already tapped stop: keep what was recognised.
      _endSession();
      return;
    }
    if (_sessionEndErrors.contains(message)) {
      _markSessionEnding();
      _finalTimer ??= Timer(finalResultTimeout, _endSession);
      return;
    }
    if (_startErrors.contains(message) && _sessionText.isEmpty) {
      _retryOrFail();
      return;
    }
    if (_languageErrors.contains(message)) {
      _fail(TranscriberEnd.languageMissing, unavailable: true);
      // Ask for the pack now; the mic comes back once it is there.
      _downloadRequested = false;
      _packWaits = 0;
      unawaited(_preparePack(afterLanguageError: true));
    } else if (_permissionErrors.contains(message)) {
      _fail(TranscriberEnd.permissionDenied);
    } else {
      _fail(TranscriberEnd.error);
    }
  }

  void _markSessionEnding() {
    if (_sessionState != _SessionState.starting &&
        _sessionState != _SessionState.listening) {
      return;
    }
    _startTimer?.cancel();
    _sessionState = _SessionState.ending;
    _sessionEndedAtMs ??= _now;
  }

  /// The current session is over: keep its text, then start the next one
  /// unless the user tapped stop.
  void _endSession() {
    if (_sessionState == _SessionState.idle) return;
    _finalTimer?.cancel();
    _finalTimer = null;
    _startTimer?.cancel();
    _sessionEndedAtMs ??= _now;
    _sessionState = _SessionState.idle;
    _commitSession();
    if (_status.value == TranscriberStatus.finishing) {
      _finished?.complete();
      _finished = null;
      return;
    }
    if (_userWantsRecording && !_disposed) _startSession(chained: true);
  }

  void _commitSession() {
    if (_sessionText.isNotEmpty) _committed.add(_sessionText);
    _sessionText = '';
    _publish();
  }

  void _onTimeLimit() {
    if (_status.value != TranscriberStatus.recording) return;
    Logs().i('Voice input: time limit reached');
    _lastEnd = TranscriberEnd.timeLimit;
    stop();
  }

  void _cancelTimers() {
    _capTimer?.cancel();
    _startTimer?.cancel();
    _finalTimer?.cancel();
    _finalTimer = null;
    _retryTimer?.cancel();
  }

  @override
  Future<String> stop() async {
    if (_status.value != TranscriberStatus.recording) return _text.value;
    _userWantsRecording = false;
    _capTimer?.cancel();
    _retryTimer?.cancel();
    _setStatus(TranscriberStatus.finishing);
    switch (_sessionState) {
      case _SessionState.listening:
      case _SessionState.ending:
        final finished = _finished = Completer<void>();
        if (_sessionState == _SessionState.listening) {
          _finalTimer ??= Timer(finalResultTimeout, _endSession);
          try {
            await _speech.stop();
          } catch (e, s) {
            Logs().w('Voice input: stop failed', e, s);
            _endSession();
          }
        }
        await finished.future;
      case _SessionState.starting:
        // Drop the session that has not started listening yet.
        _session++;
        _sessionState = _SessionState.idle;
        await _speech.cancel().catchError((_) {});
      case _SessionState.idle:
        break;
    }
    if (_disposed || _status.value != TranscriberStatus.finishing) {
      return _text.value;
    }
    _cancelTimers();
    _sessionState = _SessionState.idle;
    _commitSession();
    _finishRecording();
    _setStatus(TranscriberStatus.ready);
    return _text.value;
  }

  @override
  Future<void> cancel() async {
    _userWantsRecording = false;
    if (!_inRecording) return;
    _cancelTimers();
    _session++;
    _sessionState = _SessionState.idle;
    _finished?.complete();
    _finished = null;
    _setStatus(TranscriberStatus.ready);
    _committed.clear();
    _sessionText = '';
    _publish();
    _finishRecording();
    await _speech.cancel().catchError((_) {});
  }

  void _fail(TranscriberEnd end, {bool unavailable = false}) {
    Logs().w('Voice input stopped: ${end.name}');
    _lastEnd = end;
    _userWantsRecording = false;
    _cancelTimers();
    _session++;
    _sessionState = _SessionState.idle;
    _finished?.complete();
    _finished = null;
    // Keep what was recognised before the error.
    _commitSession();
    _finishRecording();
    _setStatus(
      unavailable ? TranscriberStatus.unavailable : TranscriberStatus.failed,
    );
    unawaited(_speech.cancel().catchError((_) {}));
  }

  void _finishRecording() {
    final stats = _lastStats = RecordingStats(
      durationMs: _clock.elapsedMilliseconds,
      restarts: _restarts,
      gapsMs: List.unmodifiable(_gapsMs),
      end: _lastEnd,
    );
    _clock.stop();
    if (_logStats()) Logs().i('Voice input recording: $stats');
  }

  @override
  void dispose() {
    if (_disposed) return;
    final active = _inRecording || _initializing;
    _userWantsRecording = false;
    _cancelTimers();
    _packTimer?.cancel();
    _finished?.complete();
    _finished = null;
    _disposed = true;
    if (active) unawaited(_speech.cancel().catchError((_) {}));
    if (_speech.statusListener == _onStatus) _speech.statusListener = null;
    if (_speech.errorListener == _onError) _speech.errorListener = null;
    _status.dispose();
    _text.dispose();
  }
}
