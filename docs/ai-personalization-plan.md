# On-device AI personalization: plan and Claude Code handoff

Oct 23, 2026 · @Simon Langbakke

## Status and decisions

Draft for review. Nothing here is approved until Simon signs off; Claude Code (CC) works one phase at a time and stops for review after each.

Decisions already made:

- **All inference runs on the client.** No message content or interaction data leaves the device for AI purposes. This keeps Matrix end-to-end encryption (E2EE) intact.
- **Heuristics first, model second.** Expert heuristics from the literature review decide *when* to suggest a change and *what* the change is. The model does only light, real-time language work.
- **Premade descriptions per heuristic.** The model does not generate explanation text in this version.
- **First feature: user-resizable UI elements**, as the literature review identified.
- **Mixed initiative.** The app suggests, the user decides. Nothing is applied without the user's confirmation, and everything can be undone.
- **Sender-side message metadata** (later phase). The sender's client annotates a message with meaning; the receiver's client decides presentation from the receiver's own settings.
- **Model: FunctionGemma 270M**, run through the flutter\_gemma plugin. It maps natural language to structured function calls, which fits a fixed set of settings.

## Architecture

&#91;embedded content: architecture · personalization on device, messages end-to-end encrypted\]

The heuristics and the model both feed the same suggestion card, so the user confirms every change. Messages leave the phone only encrypted, with the metadata inside.

## Hard constraints

These apply to every phase. CC must treat them as rules, not suggestions.

1. **No data leaves the device for AI.** No network calls for inference, no remote analytics, no crash reporters that capture message text. Interaction signals stay local.
2. **Accessibility settings stay local in phase 1.** Matrix account data is not end-to-end encrypted, so syncing settings there would let the server see them. Settings can reveal disabilities, which is sensitive. Server sync is a later, separate decision.
3. **Message metadata lives inside the encrypted message content**, under our own namespace. Never in relations or room state, which stay in plaintext.
4. **The model never applies a change directly.** Every model output is parsed, checked against an allowlist of functions and value ranges, and shown to the user for confirmation.
5. **The app must work fully without the model.** If the model is missing, still downloading, or fails, the heuristics and manual settings still work.
6. **Emulator limitation.** flutter\_gemma's `.litertlm` engine is arm64-only on Android. An x86\_64 emulator cannot run it ([flutter\_gemma docs](https://pub.dev/packages/flutter_gemma/versions/0.14.2)). Model work needs an arm64 emulator (Apple Silicon host) or a real Android phone. Phases 0 to 2 run fine on any emulator.
7. **Licenses.** FluffyChat is AGPL-3.0, so the fork's source must be available to anyone we give the app to, including study participants. FunctionGemma is under the Gemma Terms of Use and is a gated download on Hugging Face, so the app must not ship a Hugging Face token. We host the model file ourselves or bundle it.
8. **Package name check.** flutter\_gemma was renamed flutter\_edge\_ai from version 2.0 ([pub.dev](https://pub.dev/packages/flutter_edge_ai)). CC must check which one the current docs point to before adding the dependency.

## Phase 0: Repo reconnaissance

**Goal:** CC maps the FluffyChat fork before changing anything, so later phases build on what exists instead of guesses. Output is a written report, no code changes.

CC reports on:

1. Flutter and Dart versions, state management approach, and folder structure.
2. How theming works: where `ThemeData` is built, whether text scaling already exists, how button and touch-target sizes are set.
3. Where user settings are stored and how a new setting would be added.
4. The message send path: where a text message's content object is built before it reaches the Matrix SDK, and whether extra fields can be added there.
5. The message render path: which widget renders an incoming text message.
6. Which interactive widgets are the main targets for resizing: send button, attach button, chat list items, back button, message bubbles, input field.
7. The emulator's ABI (`adb shell getprop ro.product.cpu.abi`) and whether an arm64 device is available.

**Done when:** a `docs/recon.md` file in the repo answers all seven points with file paths. CC stops and waits for review.

## Phase 1: Resizable UI foundation

**Goal:** users can resize UI elements manually. No AI and no heuristics yet. This is the adaptable baseline (Fischer's sense) that every later phase plugs into, and the thing a suggestion will eventually change.

Tasks:

1. Create an `AccessibilitySettings` model with one scale factor per element category, for example `textScale`, `buttonScale`, `touchTargetScale`, `avatarScale`. Each has a min, max and step, defined in one place. That same definition becomes the allowlist in Phase 3.
2. Persist settings locally using the app's existing settings mechanism found in Phase 0.
3. Expose settings to the widget tree through a `ThemeExtension` or the app's existing state approach, so widgets read sizes from settings instead of constants.
4. Wire the scale factors into the target widgets from Phase 0, point 6. Touch targets should never drop below 48 by 48 dp, the Android minimum.
5. Add a settings screen with a slider per category and a live preview, plus a reset button.
6. Add an undo for the last change, kept in memory. Phase 2 reuses it.

**Done when:** every category visibly changes the target widgets on the emulator, settings survive an app restart, and nothing overflows or clips at the max scale. CC stops for review.

**Out of scope:** heuristics, model, server sync of settings.

## Phase 2: Interaction signals, heuristics engine, suggestion UI

**Goal:** the app notices interaction problems and suggests a resize, using rules only. This is the rule-based adaptive layer, and it works with no model at all.

Tasks:

1. **Signal collection.** Wrap the target widgets in a `TrackedTarget` widget that registers its on-screen rectangle. A root-level pointer listener classifies each tap as a hit, a near miss (lands within a set distance of a target but outside it), or a repeated tap. Pinch-zoom attempts on text are logged too. Signals are kept in memory as a rolling window and never leave the device.
2. **Heuristics engine.** Heuristics are data, not code: a JSON file in the app assets, one entry per heuristic. The engine evaluates them against the rolling window and emits candidate suggestions. The team fills in the real heuristics from the literature review.
3. **Suggestion UI.** A small, non-blocking card: the premade description, a preview of the change, and three actions: apply, not now, don't suggest this again. Applied changes can be undone from the card for a set time.
4. **Rate limiting.** At most one open suggestion at a time, a cooldown per heuristic, and permanent opt-out per heuristic.

Heuristic entry format (the two rows are placeholders to show the shape, not literature values):

| id | source | signal | condition | suggested change | description shown |
| --- | --- | --- | --- | --- | --- |
| near-miss-buttons | TBD from lit review | near misses on buttons | TBD share of taps over TBD taps | buttonScale +1 step | TBD premade text |
| text-zoom | TBD from lit review | pinch-zoom on messages | TBD attempts in TBD minutes | textScale +1 step | TBD premade text |

**Done when:** on the emulator, deliberate near misses trigger the matching suggestion, apply and undo both work, and the rate limits hold. CC stops for review.

**Out of scope:** the model. Real thresholds are the team's job, not CC's.

## Phase 3: On-device model with FunctionGemma

**Goal:** the user can say or type what bothers them ("the buttons are too small") and the app proposes the matching settings change. This is the user-initiated half of mixed initiative.

Tasks:

1. **Inference interface.** A Dart interface, for example `SettingsIntentModel`, with one method that takes the user's text and returns a proposed function call or nothing. The rest of the app only knows this interface, so the model can be swapped later.
2. **flutter\_gemma implementation.** Add the plugin and FunctionGemma 270M, which the plugin lists as about 284 MB with function calling supported ([pub.dev](https://pub.dev/packages/flutter_gemma/versions/0.14.2)). The package ships instruction files for coding assistants (`dart run skills@ get --all`); CC should install and read them first.
3. **Functions from settings.** Generate the function declarations from the Phase 1 settings definition: one function per category, with the allowed range. One source of truth means the model can never be offered a setting the app does not have.
4. **Validation.** Parse the call, check the function name and value against the allowlist, clamp or reject. A rejected call shows a fallback: "I didn't catch that" plus a shortcut to the manual settings screen.
5. **Confirmation.** A valid call reuses the Phase 2 suggestion card: preview, apply, undo.
6. **Model delivery.** Download on first use from a URL we control (our own server, no Hugging Face token in the app), with progress shown. Before the model is ready, the input is hidden and everything else works.
7. **Lazy loading.** Load the model only when the user opens the input, and release it after a period of no use, to save memory and battery.

Two known pitfalls:

- FunctionGemma expects instructions in the `developer` role, not `system`. With `system` it ignores the tools ([Medium guide](https://medium.com/google-developer-experts/on-device-function-calling-with-functiongemma-39f7407e5d83)). The plugin may handle this; CC verifies.
- This phase needs an arm64 device (see Hard constraints, point 6).

**Done when:** on an arm64 device, a test list of at least 20 phrases (English and Danish) produces correct calls or a clean rejection, nothing is ever applied without confirmation, and the app works with the model absent. CC stops for review.

**Out of scope:** fine-tuning. If base accuracy is too low, fine-tuning on data generated from our heuristics is a separate Python track, using Google's documented FunctionGemma fine-tune and `.litertlm` conversion path ([Google AI](https://ai.google.dev/gemma/docs/mobile-actions)).

## Phase 3b: Assist tab with heuristics as the model's knowledge

**Goal:** the model becomes the "expert" in a mixed-initiative setup. It proposes UI changes from the user's prompt and the UX heuristics. Nothing suggests a change without a prompt. Where this conflicts with Phases 2 and 3, Phase 3b wins.

Flow, in the Assist tab (from the `ui-enhancements` navigation):

1. The user types a prompt about the UI, e.g. "the buttons are hard to hit".
2. FunctionGemma picks the heuristic that fits the prompt.
3. The tab shows the heuristic's premade description and a live before/after preview of the affected element, and asks for confirmation.
4. The user taps Apply or No thanks. After Apply, Undo is available for `undoSeconds`.

Design:

- **Heuristics are the model's functions.** Each heuristic in `assets/personalization_heuristics.json` has a `rule`: one plain English sentence on the problem it addresses and the change that helps. Each heuristic with a rule becomes one function, `heuristic_<id>`, whose description is the rule and whose only parameter is `steps` (1 to 3). Which setting changes and in which direction come from the heuristic's `change`, never from the model. The old `adjust_*` functions are not offered; `SettingsCallValidator` still checks the resulting change against the allowed ranges.
- **No invented changes.** No call, an unknown function or unusable arguments show "I don't have a suggestion for that" and a link to the manual Accessibility settings.
- **No unprompted suggestions.** Interaction signals, the heuristics engine and the overlay suggestion card are disconnected but kept in the repo, marked as disabled. The `condition` fields in the heuristics file are unused.
- **The model is confined to the Assist tab.** The tab creates the model when it opens and disposes it when it closes; no engine starts at app start. Each prompt goes to a fresh chat with only the prompt text and the heuristic functions, never rooms, events, timelines or messages. `function_gemma_model.dart` is the only file that imports `flutter_edge_ai`.
- **States.** Model unavailable (the tab explains this and links to manual settings), not prepared, preparing with progress, failed with retry, ready.

**Open:** the two heuristics and their rules are still placeholders until the team adds literature-based ones. With only two heuristics, most prompts correctly get no suggestion.

## Phase 4: Sender-side message metadata

**Goal:** the sender's client attaches meaning to a message; the receiver's client uses it to present the message according to the receiver's settings. Phase 1 only covers FluffyChat users, so every message in the study can carry metadata.

Tasks:

1. **Schema.** Version 1 describes meaning, never presentation: intent (question, information, request), urgency, and extracted entities such as times and dates. A `v` field allows changes later. The namespace string is an open question for the team.
2. **Send path.** Add the metadata object next to `body` in the message content at the point found in Phase 0. It is encrypted with the rest of the content.
3. **Annotation.** The sender's model proposes the metadata as a function call (for example `annotate_message(intent, urgency, time)`), and the sender sees and can correct it before sending. This lets the sender confirm meaning at the source.
4. **Render path.** The receiver's client reads the metadata and adjusts presentation from the receiver's settings, for example a question marker, or a highlighted time with an "add to calendar" action. The original text is always one tap away.
5. **Fallbacks.** Missing, unknown-version or invalid metadata means the plain `body` is shown. Edited messages get new metadata in their replacement content (`m.new_content`).

**Done when:** two emulator accounts exchange annotated messages, Element shows them as normal text, and an edited message updates its metadata. CC stops for review.

**Decided (Oct 26, 2026):**

- Namespace: `dk.aau.sw9.meaning`.
- Because of Phase 3b (the model never sees message content), the metadata is proposed by simple English and Danish rules instead of the model: a question mark or question word for questions, request phrases, urgent words, and time and date patterns. The sender sees the proposal as chips above the input and can change or remove it before sending, and can turn it off in the Accessibility settings.
- The receiver chooses in the Accessibility settings whether questions and requests are marked, urgent messages are marked, and times are highlighted. Times are highlighted only, with no calendar action.

**Out of scope:** free-text rewriting (a `plain` simplified version). No model at this size does it well enough, and it needs its own decision.

## Phase 5: Evaluation harness and study logging

**Goal:** measurable results for the thesis, without breaking the privacy constraints.

Tasks:

1. **Model test harness.** An integration test that runs a fixed phrase list (input, expected call) through the real model on device and reports accuracy and latency (time to first token, total). The phrase list lives in the repo so the team can grow it.
2. **Study event log.** A local, append-only log of study events: suggestion shown, applied, dismissed, undone, opted out, model call proposed, confirmed, rejected. It records heuristic ids, setting values and timestamps. It never records message text.
3. **Export.** A hidden screen where a participant, with the researcher present, exports the log as a file. Nothing is uploaded automatically.
4. **Study condition switch.** A hidden toggle for heuristics only, heuristics plus model, or manual only, so the same build can run different study conditions.

**Done when:** the harness runs on a real device and prints a report, and an exported log contains no message content. CC stops for review.

**Important:** accuracy and latency numbers for the thesis come from a real low-end arm64 phone running the deployed runtime, never from the emulator.

## Open questions

These need answers from Simon or the team. CC must not decide them.

- [ ] Which heuristics from the literature review go in, with which signals and thresholds?
- [ ] Is the emulator x86\_64 or arm64, and which real arm64 phone do we test the model on?
- [ ] Which UI elements are in scope for resizing in the first version?
- [ ] Will participants interact in Danish, English or both? This decides the test phrase list and any fine-tuning data.
- [x] Namespace string for the message metadata: `dk.aau.sw9.meaning` (decided Oct 26, 2026).
- [ ] Model delivery: download from our own server on first use, or bundle it in the APK for the study build?
- [ ] Is the study event log covered by the ethics and consent plan as described in Phase 5?
- [ ] Phase order: is Phase 4 (metadata) needed for the first study, or can it come after?

## Claude Code handoff

Export this doc as Markdown, save it in the repo as `docs/ai-personalization-plan.md`, then paste the prompt below into Claude Code from the repo root.

```markdown
You are working in our fork of FluffyChat (Flutter, Matrix). We are building
an accessibility-personalization feature for elderly users as part of an HCI
master's thesis. The full plan is in docs/ai-personalization-plan.md. Read it
completely before doing anything.

How to work:
- Work one phase at a time, in order, starting with Phase 0.
- At the start of each phase, write a short plan of the files you will change
  and wait for my approval before editing code.
- At the end of each phase, run the app on the Android emulator (already set
  up), check every "Done when" item, report what passed and what did not,
  then STOP and wait for review. Do not start the next phase on your own.
- Never decide anything listed under "Open questions". If you hit one, ask.
- If the code contradicts the plan, tell me instead of working around it.

Rules that apply to every phase (see "Hard constraints" in the plan):
- No data leaves the device for AI. No network calls for inference, no remote
  analytics, nothing that captures message text.
- Accessibility settings are stored locally only. Never in Matrix account data.
- Message metadata goes inside the message content object, never in relations
  or room state.
- The model never applies a change directly. Every output is validated
  against the allowlist and confirmed by the user.
- The app must work fully without the model.
- Keep changes small and isolated from upstream FluffyChat code where
  possible, so we can still merge upstream updates. Put new code in its own
  folder.
- Write tests for the settings model, the heuristics engine and the
  validation logic.

Before Phase 3: check whether the on-device package is currently published as
flutter_gemma or flutter_edge_ai, install its coding-assistant skills
(dart run skills@ get --all) and read them. The .litertlm engine is arm64 only
on Android, so tell me if the emulator is x86_64.

Start with Phase 0 now.
```
