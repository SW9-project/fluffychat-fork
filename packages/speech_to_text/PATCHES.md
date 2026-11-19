# Local patches to speech_to_text

This is [speech_to_text](https://pub.dev/packages/speech_to_text) 7.5.0 from
pub.dev (BSD-3-Clause, see `LICENSE`), copied without its `example/` folder
and patched by SW9-project for the Assist voice input
(`lib/personalization/voice/`).

## Why

Hard constraint 1 in `docs/ai-personalization-plan.md`: no data leaves the
device for AI. Upstream, `listen(onDevice: true)` on Android only gets the
local-only recognizer (`SpeechRecognizer.createOnDeviceSpeechRecognizer`) when
the device runs Android 12 (API 31) or later and
`SpeechRecognizer.isOnDeviceRecognitionAvailable` is true. Otherwise it
silently creates the default recognizer, which may send audio to a server,
and only adds `EXTRA_PREFER_OFFLINE` as a hint. The `androidIntentLookup`
option skipped the on-device path completely.

## What changed

All changes are marked `SW9 patch` in the source.

Android, `android/src/main/kotlin/com/csdcorp/speech_to_text/SpeechToTextPlugin.kt`:

1. `startListening`: with `onDevice` true and no on-device recognition, the
   call fails with error code `onDeviceUnavailable` (message and details
   contain `onDeviceUnavailable`). In Dart this is a `ListenFailedException`.
2. `createRecognizer`: with `onDevice` true, only the on-device recognizer is
   ever created. No intent lookup, no default recognizer.
3. `startListening`: if no recognizer exists when listening should start, the
   plugin sends the error `error_recognizer_unavailable` and the
   `notListening` status instead of reporting that it is listening.
4. `onMethodCall`: implements `has_on_device_support`, which the platform
   interface already declares (`SpeechToTextPlatform.hasOnDeviceSupport`) but
   upstream Android does not answer. It returns the same check as change 1
   and needs no permission or `initialize`. The `localeId` argument is
   ignored: Android only reports whether an on-device service exists, not
   whether a language pack is installed.

5. `sendError`: on the main thread (where recognizer callbacks arrive), the
   error is sent at once instead of posted. Upstream, `onError` posted the
   error but sent `notListening` and `done` directly, so Dart saw the end of
   the session before its error. Found on a Samsung S22 Ultra, Android 16: the
   app restarted on `done`, then took the late `error_no_match` or language
   error for the new session.
6. `onResults`: the final result ends the listening state at once
   (`notListening`, then `done`), instead of after the plugin's end-of-speech
   timer (1 s by default). Without it the app had to call `stop` on a finished
   session to restart quickly, and Android System Intelligence answers that
   with `ERROR_CLIENT`, which arrived after the next session had started.
7. `cancelListening`: when the plugin no longer tracks a session (after an
   error), it still cancels the recognizer. On the S22 Ultra a session the
   plugin had given up on kept the mic for about 10 seconds, and every new
   `listen` in that time failed with `error_client`.
8. `onEndOfSpeech`: only one end-of-speech timer exists at a time, a new
   `listen` cancels it, and a timer from an earlier session is ignored.
   Android System Intelligence calls `onEndOfSpeech` twice per session.
   Upstream armed a second timer and lost the first, which fired a second
   later during the next session and reported it as ended. The app then
   started another session while the real one was still running, and Android
   answered with `error_client`.

iOS and macOS, `darwin/speech_to_text/Sources/speech_to_text/SpeechToTextPlugin.swift`:

9. `listenForSpeech`: when on-device recognition is not supported, the call
   now returns after the `onDeviceError` result (upstream went on to listen),
   an OS without on-device support counts as unsupported, and the message and
   details contain `onDeviceUnavailable`.
10. `handle`: implements `has_on_device_support` like change 4, but for the
    `localeId` argument (`SFSpeechRecognizer.supportsOnDeviceRecognition`
    is per language). Needs no permission or `initialize`.
11. `didFinishSuccessfully`: an unsuccessful session sends its error before
    `doneNoResult` instead of after it, for the same reason as change 5.

Nothing in `lib/` is changed.

## Updating

1. Copy the new upstream version over this folder, keeping this file and
   leaving out `example/`.
2. Re-apply the eleven changes above, or drop any that upstream has fixed.
3. Bump `version` in `pubspec.yaml` (`<upstream>+sw9.<n>`).
4. Run `flutter test test/personalization/`, then check on a real Android
   phone in airplane mode that voice input still works.
