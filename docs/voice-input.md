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
  On a final result the app stops the session itself instead of waiting for
  the plugin's one-second end-of-speech timer, and starts the next one only
  after that stop returns (otherwise the plugin's own final-result timer would
  cut the next session short).
- A session that fails to start is retried once after 300 ms, then the
  recording stops with a message. The recogniser is never destroyed between
  sessions.
- Recording stops by itself only after 2 minutes, with a message. The text
  is kept.
- `error_language_unavailable` or `error_language_not_supported` hide the mic
  and explain how to install the English pack. `error_permission` and a
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
- Not built, waiting for Simon: the `assist_voice` timing event, step 7 (the
  English pack check), `WhisperTranscriber`.

## Step 0: English pack measurement

To be filled in by Simon on a real phone (Settings, Apps, "Speech Recognition
and Synthesis" or "Speech Services by Google", Storage).

| Phone and Android version | Language | App + data before | After download | Pack size | Offline pack offered |
| --- | --- | --- | --- | --- | --- |
| | English (US) | | | | |
| | Danish | | | | |

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

- [ ] Airplane mode on: voice input still works.
- [ ] A sentence with a 3 second pause: missing words.
- [ ] A sentence with a 10 second pause: missing words.
- [ ] Speaking right after a restart sound: are the first words lost?
- [ ] 30 seconds of silence after tapping the mic, then speaking: still
  recording, words appear.
- [ ] How often the restart sound plays, and whether it feels like an error.
- [ ] Restart counts and gaps from the log.
- [ ] Transcribe, then send at once: FunctionGemma answers, no crash.
- [ ] English pack removed: install message, typing works, nothing sent.
- [ ] Microphone permission denied: explanation, typing works.

| Test | Result | Restarts | Gaps (ms) |
| --- | --- | --- | --- |
| 3 s pause | | | |
| 10 s pause | | | |
| 30 s silence | | | |

Decision rule from the spec: if words are regularly lost after pauses, or the
restart sound reads as something breaking, switch to `WhisperTranscriber`
behind the same interface. Otherwise keep the native recogniser.

## Known limits

- Words spoken during a restart can be lost, and Android plays a sound at
  each restart. The real-device test measures both.
- Needs Android 12 or later, Google's speech service with on-device
  recognition, and the English offline pack. Study phones must be prepared
  beforehand.
- Whether the English pack is installed only shows on the first recording.
  Step 7 would check it in advance on Android 13 and later.
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
