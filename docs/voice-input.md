<!--
SPDX-FileCopyrightText: 2026 SW9-project contributors

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Phase 3c: Voice input for Assist

Date: 2026-11-16. Branch `feat/STT-TTS`, based on `main` at `348d6bc1e`.
Spec: "Voice input for Assist (local speech to text)" (Claude Doc). Plan:
[ai-personalization-plan.md](ai-personalization-plan.md), whose hard
constraints all apply.

The user taps the mic in the Assist tab, speaks for as long as they need,
and taps again to stop. The words land in the prompt field, and the user
checks them and taps send. Recognition runs on the phone only, in English.

## What was built

| Part | Where |
| --- | --- |
| Engine-neutral interface: status, live text, `lastEnd`, start, stop, cancel | `lib/personalization/voice/speech_transcriber.dart` |
| `SystemTranscriber`: the phone's recogniser, on-device only, with session chaining | `lib/personalization/voice/system_transcriber.dart` |
| Patched `speech_to_text` 7.5.0 that never falls back to the network | `packages/speech_to_text/` ([PATCHES.md](../packages/speech_to_text/PATCHES.md)) |
| Mic button, recording states and messages | `lib/personalization/assist/assist_view.dart` |
| Transcriber created next to the model, Assist condition only | `lib/pages/assistant/assistant_page.dart` |
| Language pack check and download (step 7, adapted) | `lib/personalization/voice/language_pack.dart`, `android/app/src/main/kotlin/chat/fluffy/fluffychat/SpeechLanguagePack.kt` |
| `voice` flag on `assist_prompt` | `lib/personalization/study/study_events.dart` |
| Strings in English and Danish | `lib/personalization/personalization_l10n.dart` |
| Android `<queries>` for `RecognitionService`, iOS speech usage text | `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` |

### How a recording works

Android ends a recogniser session after a short pause, and that cannot be
turned off. `SystemTranscriber` starts a new session at once whenever one ends
by itself, until the user taps stop, and joins the sessions' text with one
space. The UI does not change between sessions. Android plays its start and
stop sound at every restart.

- Every `listen` call passes `onDevice: true`. The patched plugin fails with
  `onDeviceUnavailable` instead of using a recogniser that may use the network.
  Before the first tap, the mic is only shown on Android 12 or later with an
  on-device recognition service, checked without asking for any permission.
- A session ends with its final result, or with `error_no_match` or
  `error_speech_timeout` when nothing was said. Both start the next session.
  The patched plugin reports the end of the session right after the final
  result, so the next session starts within milliseconds. The app never calls
  `stop` on a finished session: Android System Intelligence answers that with
  `ERROR_CLIENT`, which then lands in the next session.
- A session that fails to start is retried once after 300 ms, then the
  recording stops with a message. The recogniser is never destroyed between
  sessions.
- Recording stops by itself only after 2 minutes, with a message. The text
  is kept.
- Every time the Assist tab opens, the app checks the English pack of the
  on-device recogniser (`checkRecognitionSupport`, Android 13 and later). If
  it is missing, the app asks the system to download it
  (`triggerModelDownload`) and shows the mic disabled with "the phone is
  downloading English speech recognition" until the pack is installed,
  checking every 5 seconds for up to 15 minutes. The system's recognition
  service fetches the pack; the app sends no audio or text. An unsupported
  language hides the mic. When the phone cannot tell (below Android 13), the
  mic is offered and the first recording finds out.
- `error_language_unavailable` or `error_language_not_supported` during a
  recording ask for the pack the same way. If no download is possible, the
  mic is hidden for the rest of the visit with a message on how to install
  the pack. `error_permission` and a
  refused permission explain what is needed. Any other error stops the
  recording with a message and keeps the words heard so far. Typing always
  works.

### Study log

`assist_prompt` has `voice: true` when spoken words were put into the field
since the last send, even if they were edited afterwards, and `false` for a
typed prompt. The flag resets on send and when the field is cleared; a
cancelled recording does not count. Lines from before this change have no
`voice` field, which means `false`. The app shows and exports log lines as
they are, so old lines still load. Audio is never written anywhere.

## Decisions and differences from the spec

- **Patched plugin instead of the pub.dev package** (Simon, 16 Nov). The
  upstream fallback broke hard constraint 1. See PATCHES.md.
- **`pauseFor` and `listenFor` are left unset** instead of set to a maximum.
  Unset, the plugin's Dart side never ends a session by its own timers. On
  Android, `pauseFor` also delays the plugin's end-of-session status after
  the end of speech, so a long value would delay every restart.
- **`ListenMode.dictation` only has an effect on iOS.** Android always uses
  free-form recognition.
- **iOS is off.** `SystemTranscriber.isSupported` only accepts Android until
  it is decided whether the study needs iOS. The iOS patch and usage text are
  in place.
- **A missing language pack hides the mic for the rest of that visit only**
  (Simon, 16 Nov). The spec said to keep it hidden on the next visit until a
  session succeeds, but a hidden mic can never succeed, so it would never come
  back after the pack is installed. On the next visit the mic shows again;
  if the pack is still missing, a tap shows the install message again.
- **Backgrounding means `hidden` or `paused`, not `inactive`.** The Android
  permission dialog makes the app inactive, and that must not cancel the
  recording that asked for the permission.
- **Step 7 is built, with an automatic download** (Simon, 16 Nov: "always
  check and download language pack when opening assist"). There is no
  "Download English speech pack" button: the download starts when the tab
  opens. The channel lives in the Android runner as the spec says, with one
  line in `MainActivity` to register it.
- **Errors arrive before the end of a session.** The first device test found
  that the plugin delivered `notListening` and `done` before the error that
  ended the session, so the app restarted and then took the old error for the
  new session. Patch change 5 in PATCHES.md fixes the order.
- **A session the app gave up on must still be cancelled.** The second device
  test (S22 Ultra, Android 16) found that after an error the plugin skipped
  `cancel`, the recognition service kept the session and the mic for about
  10 seconds, and every tap in that time failed at once. Patch changes 6 and 7
  end sessions on the final result and always pass `cancel` on. A start
  followed by a cancel within milliseconds (the bug fixed by change 5) also
  left Android System Intelligence's audio capture stuck until the next
  successful stop, so the first recording after it heard nothing.
- **One end-of-speech timer per session.** The third device test found every
  recording stopping about a second after the first sentence
  (`restarts=2 end=restartFailed`). Android System Intelligence reports the
  end of speech twice, and the plugin's second timer replaced the first
  without cancelling it. The lost timer then ended the next session while it
  was still listening. Patch change 8 fixes it.
- Not built: the `assist_voice` timing event (waiting for Simon), and
  `WhisperTranscriber` (not needed after the device test, see below).

## Step 0: English pack measurement

On the test phone the on-device recogniser is Android System Intelligence
(`com.google.android.as`), not "Speech Services by Google"
(`com.google.android.tts`, 108.6 MB app + 1145 MB data, unchanged by the
download). Sizes from `adb shell dumpsys diskstats`, which Android updates
from time to time, so they are approximate. "Before" was measured on 16 Nov
at 18:33, the en-US download finished at 19:46, "after" on 17 Nov. The phone
already had the en-GB pack.

| Phone and Android version | Language | App + data before | After download | Pack size | Offline pack offered |
| --- | --- | --- | --- | --- | --- |
| Samsung Galaxy S22 Ultra (SM-S908B), Android 16 | English (US) | 124.2 + 305.2 MB | 123.9 + 398.3 MB | 62.06 MB download (system dialog), about 93 MB more data | Yes: the app's request opened the system dialog "Download English (US) update" |
| | Danish | not measured | | | |

## Real-device test (Checkpoint B)

On an arm64 Android phone with the English offline pack installed, in a
debug build or with study logging on. After each recording the app logs one
line with the restart count and the gap between a session ending and the next
one listening, in this format (the numbers are only an example):

```
Voice input recording: duration_ms=41250 restarts=4 gaps_ms=[612, 588, 701, 640] end=user
```

Read it with `adb logcat -s flutter | grep "Voice input recording"` or in the
app's log viewer (`/logs`). It never contains audio or text.

`gaps_ms` runs from the end of one session to the plugin reporting the next
one as listening. The microphone opens later than that. The real time with
the microphone closed shows in the recognition service's own log: from
`SodaSpeechRecognizer #handleFinalResult` to the next
`RecognitionService#onMicrophoneOpened`.

### Results, 17 Nov 2026

Samsung Galaxy S22 Ultra, Android 16, Android System Intelligence with the
SODA en-US pack, debug build with the timer fix (patch change 8). Six
recordings, all stopped by the user's tap. No `error_client`, no
`restartFailed`.

| Recording | Length | Restarts | After speech / after silence | `gaps_ms` | Microphone closed per restart (ms) |
| --- | --- | --- | --- | --- | --- |
| 1 | 11.2 s | 2 | 1 / 1 | 2, 6 | 344, 340 |
| 2 | 12.5 s | 2 | 1 / 1 | 1, 5 | 310, 308 |
| 3 | 17.1 s | 2 | 2 / 0 | 2, 1 | 297, 322 |
| 4 | 6.6 s | 0 | – | – | – |
| 5 (30 s silence, then "hello") | 33.3 s | 4 | 0 / 4 | 3, 4, 3, 1 | 293, 288, 310, 427 |
| 6 (airplane mode on) | 6.3 s | 1 | 1 / 0 | 3 | 322 |

- The microphone is closed for about 0.3 seconds at each restart (288 to
  427 ms, 12 restarts). Words spoken in that time are lost.
- A silent session ends after about 5.4 seconds (`error_speech_timeout`), so
  silence restarts the recogniser and plays the sound about every 5 seconds.
  One silent session lasted 12.4 seconds.
- In recording 1 the recogniser heard speech only in the first session
  (1.3 s). Whether the second half of the sentence was said or lost cannot be
  told from the log, which holds no text.

- [x] Airplane mode on: voice input still works (recording 6, speech
  recognised with airplane mode on).
- [x] A sentence with a 3 second pause: no missing words (Simon, from the
  text in the field).
- [x] A sentence with a 10 second pause: no missing words (Simon).
- [ ] Speaking right after a restart sound: are the first words lost? Not
  tested on purpose. The microphone is closed for about 0.3 s per restart.
- [x] 30 seconds of silence after tapping the mic, then speaking: still
  recording, words appear (recording 5).
- [x] How often the restart sound plays, and whether it feels like an error.
  About every 5 seconds in silence, and after every sentence. Simon: it
  sounds like a new session starting, not like an error.
- [x] Restart counts and gaps from the log (table above).
- [ ] Transcribe, then send at once: FunctionGemma answers, no crash. Not in
  the log of this run.
- [x] English pack missing: install message, typing works, nothing sent
  (16 Nov, `error_language_unavailable`, then the automatic download).
- [ ] Microphone permission denied: explanation, typing works.

Decision rule from the spec: if words are regularly lost after pauses, or the
restart sound reads as something breaking, switch to `WhisperTranscriber`
behind the same interface. Otherwise keep the native recogniser.

**Decision (Simon, 17 Nov 2026): keep the native recogniser.** No words were
missing and the restart sound did not read as an error. `WhisperTranscriber`
is not built.

## Known limits

- Words spoken during a restart can be lost: the microphone is closed for
  about 0.3 seconds each time. Android plays a sound at each restart, which
  is after every sentence and about every 5 seconds of silence.
- Needs Android 12 or later, Google's speech service with on-device
  recognition, and the English offline pack. Study phones must be prepared
  beforehand.
- Below Android 13, whether the English pack is installed only shows on the
  first recording, and the app cannot download it.
- The pack download needs network and may wait for Wi-Fi; the system
  decides. Study phones should still get the pack before a session.
- FunctionGemma was trained on typed phrasing. Spoken requests are looser, so
  spoken-style phrases should be added to the model test set before the
  study.
- The `speech_to_text` Windows, macOS and web parts are built into those apps
  but unused. CI builds for them were not run locally.

## Tests

`flutter test test/personalization/` covers the spec's automated acceptance
list:

| Acceptance item | Test file |
| --- | --- |
| No mic when the transcriber is null or unavailable; the tab still works | `assist_view_test.dart` |
| Mic starts recording; stop icon, "Listening" text and timer | `assist_view_test.dart` |
| A session the platform ends starts a new one; text joined with one space | `system_transcriber_test.dart`, `assist_view_test.dart` |
| No match and speech timeout start a new session | `system_transcriber_test.dart` |
| Other errors stop the recording with a message | both |
| Only the user's tap stops a recording before the 2 minute cap | `system_transcriber_test.dart` |
| Every `listen` call has `onDevice: true` | `system_transcriber_test.dart` |
| Stop shows finishing, then the text stays in the field | `assist_view_test.dart` |
| No `assist_prompt` until send | `assist_view_test.dart` |
| Appended after existing text; an empty result leaves the field unchanged | `assist_view_test.dart` |
| Send disabled while recording and finishing | `assist_view_test.dart` |
| `voice` true for spoken, false for typed, resets after send | `study_log_test.dart`, `assist_view_test.dart` |
| A log line without `voice` still loads | `study_log_test.dart`, `study_screen_test.dart` |
| Disposing the view during a recording cancels it | `assist_view_test.dart` |
