# On-device AI personalization: plan and Claude Code handoff

Oct 23, 2026 · @Simon Langbakke

## Status and decisions

Draft for review. Nothing here is approved until Simon signs off; Claude Code (CC) works one phase at a time and stops for review after each.

Decisions already made:

- **All inference runs on the client.** No message content or interaction data leaves the device for AI purposes. This keeps Matrix end-to-end encryption (E2EE) intact. *Changed for the Assist tab by Phase 6 (Nov 8, 2026): it may ask an online model through our proxy. Phase 6b (Nov 11, 2026): for development and the study it asks Groq directly.*
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

1. **No data leaves the device for AI.** No network calls for inference, no remote analytics, no crash reporters that capture message text. Interaction signals stay local. *Phase 6 exception: the Assist tab sends the typed prompt and the size settings to our proxy; see Phase 6 for exactly what is sent. Phase 6b: in development and study builds it sends them straight to Groq.*
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
6. **Model delivery.** Download on first use from a URL we control (a public GitHub release, no token in the app), with progress shown, and check its SHA-256 before use. Before the model is ready, the input is hidden and everything else works. See `assets/models/README.md`.
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

- **Heuristics are the model's functions.** Each heuristic in `assets/personalization_heuristics.json` has a `rule`: one plain English sentence on the problem it addresses and the change that helps. Each heuristic with a rule becomes one function, `heuristic_<id>`, whose description is the rule and whose only parameter is `steps` (1 to 3). Which setting changes and in which direction come from the heuristic's `change`, never from the model. A `direction` parameter was tried after the code review and removed (see "Code review fixes"). The old `adjust_*` functions are not offered; `SettingsCallValidator` still checks the resulting change against the allowed ranges.
- **No invented changes.** No call, an unknown function or unusable arguments show "I don't have a suggestion for that" and a link to the manual Accessibility settings.
- **No unprompted suggestions.** Interaction signals, the heuristics engine and the overlay suggestion card are disconnected but kept in the repo, marked as disabled. The `condition` fields in the heuristics file are unused.
- **The model is confined to the Assist tab.** The tab creates the model when it opens and disposes it when it closes; no engine starts at app start. Each prompt goes to a fresh chat with only the prompt text and the heuristic functions, never rooms, events, timelines or messages. `function_gemma_model.dart` is the only file that imports `flutter_edge_ai`.
- **States.** Model unavailable (the tab explains this and links to manual settings), not prepared, preparing with progress, verifying the checksum, failed with retry, ready. A download goes on when the tab closes, and the tab shows it again on return.

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

**Decided (Oct 27, 2026):**

- Two study conditions, because since Phase 3b the heuristics only reach the user through the model, so "heuristics only" has no UI. **Assist**: the Assist tab with the on-device model (also the normal app). **Manual only**: the Assist tab says the assistant is off and links to the Accessibility settings, and no model is created.
- Logging is off until the researcher turns it on in the study screen, after the participant agreed. The ethics question below stays open.
- The log keeps the words participants type in the Assist tab, so the model can be checked against real requests. Prompts can describe health or disabilities, so the consent must cover them. The log never keeps message text: for a message with meaning it keeps the intent, the urgency and how many times it mentions.
- Hidden study screen: hold the title of the Accessibility page for three seconds. It sets the condition (with a confirmation) and the participant code, turns logging on and off, shows the latest events, and saves the log through the system save dialog. Nothing is uploaded.
- Format: one JSON object per line in the app's private storage, with UTC timestamps and the participant code on every line. The app only appends; the study screen can **Save and clear** (cleared only after the file is saved, for the next participant) or **Delete log** (for a participant who withdraws), both with a confirmation, and the next log starts with `log_cleared`. An export starts with a header line: participant code, condition, app version and device.
- Events: `logging_started`, `logging_stopped`, `condition_changed`, `log_exported`, `assist_opened`, `assist_model_state`, `assist_prompt`, `assist_proposal` / `assist_at_limit` / `assist_no_suggestion` (with time to first token, total time and tokens), `suggestion_applied` / `_declined` / `_undone` / `_opted_out` / `_superseded` (a new prompt replaced it) / `_abandoned` (the participant left the tab without answering), `log_cleared`, `settings_changed` (slider, apply, reset or undo, with each value's from and to), `meaning_changed`, `meaning_removed`, `meaning_sent`, `meaning_settings`.
- A `meaning_sent` without a `meaning_changed` before it means the sender did not correct the proposal, not that they confirmed it: annotation is on by default.
- Study phones run a study build (`scripts/build_study_apk.sh`), which holds the model, so a session does not depend on Wi-Fi and the phone contacts no download server. Before each session the researcher taps Set up in the Assist tab, so the model copy (about 40 s on the S22 Ultra) and its checksum are not part of the session. Every participant who gets the app must also receive the Gemma Terms of Use (see `assets/models/README.md`).
- Harness: `integration_test/personalization_model_test.dart` reports per phrase the outcome, the time to first token as LiteRT-LM measures it (FunctionGemma's tool call is not streamed), the total time and the token counts, plus a `[phrases-csv]` line for a spreadsheet. The summary gives accuracy per language and the median, p90 and maximum. Loading the model is reported once, apart from the totals.

## Code review fixes (Oct 27, 2026)

From the review of Phases 0 to 5 at `bc3f965`:

1. The two placeholder descriptions no longer claim the app watched taps or zooming; they describe the change ("Bigger buttons are easier to hit. Make the buttons bigger?").
2. The before/after preview stacks the two samples, so on a phone they no longer shrink to the same width.
3. Tried and reverted: a required `direction` parameter (bigger or smaller), with no suggestion when it contradicted the heuristic. On the S22 Ultra it lowered the phrase test from 16 of 22 to 12 of 22, and to 13 of 22 with a clearer description, because the model writes the problem as the direction ("too small" becomes `smaller`) and calls functions less often. So "the letters are too big" can still get a proposal for bigger text; the preview and the Apply step catch it. A real fix needs a "make smaller" heuristic from the literature, or a bigger model.
4. Clock times from 1 to 12 without am/pm keep only the sender's words; a named day is still resolved to its date. "at" counts as a time marker only with minutes or am/pm (in Danish it means "that" or "to").
5. "ses", "have" and "will" are no longer question words.
6. The study log has the participant code on every line, and the study screen can save and clear or delete it.
7. Proposals replaced by a new prompt or left open when the tab closes are logged as superseded or abandoned.

Also: after Apply, the Assist tab points to the Accessibility settings to change it back, and the error dialog no longer has a Report button, which sent the error to upstream FluffyChat's GitHub. Not changed, for the team to decide: `undoSeconds` (placeholder), touch area instead of icon size for missed taps, and the slider lag check on a cheap phone.

## Phase 6: Online model in the Assist tab, on-device model as fallback

Nov 8, 2026 · decided by @Simon Langbakke

**Goal:** better understanding of natural language than the 270M on-device model (16 of 22 phrases on the S22 Ultra). The Assist tab now asks a bigger model on a free API tier, through our own proxy next to Synapse. The on-device pilot model stays as the offline fallback.

**What changes from earlier decisions.** Phase 6 wins over the following:

- **Hard constraint 1 and "All inference runs on the client".** These no longer hold for the Assist tab. The constraint still holds for everything else in the app.
  - **What leaves the phone:** the text typed in the Assist tab, at most the one exchange before it when the assistant asked a question, the current values of the five size settings, the system prompt, and the tool schemas.
  - **Before sending,** the app removes Matrix IDs, room aliases, links and e-mail addresses from the text.
  - **What never leaves the phone:** messages, rooms, contacts, timelines, interaction signals.
  - **Enforcement:** `AssistRequest` has no field for anything else, and `RemoteAssistBackend` is the only code that builds the request. A test fails if anything outside the Assist tab creates a backend.
  - **Not covered:** names typed as plain words in a prompt cannot be told apart from other words, so they are sent.
- **Constraint 2 (settings can reveal disabilities).** The five size values now reach the proxy and Groq with every Assist request. They are not stored in Matrix account data, so constraint 2 itself holds.
- **Phase 3b, "the model only picks a heuristic".** This now applies only to the on-device model.
  - The online model gets one `set_<setting>` tool per setting in `lib/personalization/settings_registry.dart`. Each tool takes three required parameters: `value`, `heuristic` (which heuristic justifies the change, from an enum) and `rationale` (one plain sentence shown to the user).
  - The on-device pilot keeps its `heuristic_*` functions unchanged, because it was fine-tuned on those exact words.
- **"Premade descriptions, the model writes no text".** The online model's `rationale` is shown instead of the premade description. The app cleans it up and cuts it to 200 characters. Without a rationale, the premade text is shown.
  - The online model may also answer with one short question when a request is unclear. Its next request includes that question and the user's answer.
- **Study builds and Wi-Fi.** With a proxy URL set, a session uses Wi-Fi. The app falls back to the on-device model when the proxy can't be reached, when every provider fails (`ASSIST_FALLBACK`), or when the user hits the rate limit. Only if that model is set up.

**How it works.**

1. The app asks Synapse for a Matrix **OpenID token**, not the access token, and sends it to `llm-proxy/`.
2. The proxy checks the token at `/_matrix/federation/v1/openid/userinfo` and accepts only users on our homeserver. It allows 10 requests per minute per user.
3. The proxy tries each provider in `config/providers.json` in order. For now that is only Groq with `openai/gpt-oss-20b`.
4. API keys exist only in the proxy's environment.
5. The proxy logs a hashed user ID, the provider, latency, token counts and the tools called. It logs prompt text only with `STUDY_LOGGING=true`.
6. The app checks every tool call with `AssistValidator`: unknown tools or heuristics are rejected, and values are clamped to the allowed range. A valid call goes through the existing preview, Apply and Undo flow.
7. Undo now keeps the last 20 changes, so the Undo button on the Accessibility page can go back through all of them.
8. Each answer is marked "Online assistant" or "On this phone".

**Heuristics for the online model** live in `assets/assist/heuristics.md`, which the team edits.

- It holds the system prompt and the heuristics per category.
- It reuses `near-miss-buttons` and `text-zoom` from `assets/personalization_heuristics.json` with the same ids, so the study log matches.
- The other five heuristics are placeholders, so that every setting has at least one heuristic.
- A request comes to about 1,500 tokens. The budget is 2,500, and the app and the proxy log a warning above it.

**Evaluation.** `llm-proxy/eval/` sends 31 generated requests in English and Danish through the proxy and reports:

- the valid tool-call rate
- the correct setting and direction
- invalid and out-of-range proposals
- latency per provider

Its prompt and tools come from a fixture that a test keeps equal to the app's.

**Not done here:**

- Mistral is left out because its free tier requires opting in to training on our requests.
- There is no study condition that forces the on-device model, for comparing the two.
- The Synapse and reverse-proxy setup on the home server is not done (see `llm-proxy/README.md`).

## Phase 6b: Groq called directly from the app (development and study only)

Nov 11, 2026 · requested on the `feat/ai-personalization` branch; a temporary setup, not a release design

**Goal:** use the online model in development and in the study without running the proxy. The app calls Groq with a key that is compiled in from `env.json` (`--dart-define-from-file=env.json`). The team accepts that the key can be extracted from any build made with it.

**What changes from Phase 6.** Phase 6b wins over the following, for now:

- **"API keys exist only in the proxy's environment."** No longer true for development and study builds. The key is in the app. `env.json` is git-ignored and `env.example.json` holds a placeholder.
- **The proxy path in the app is removed.** `RemoteAssistBackend`, the OpenID token source and the `assistProxyUrl` setting are gone (commit `a43ff0ce2`). The `llm-proxy/` server code stays.
  - The shared request and answer format now lives in `AssistChatFormat`. A proxy backend can come back as one class next to `GroqAssistBackend`.
  - **Before any public release** the app must go back to a proxy. `GroqAssistBackend` carries a `TODO(dev-only)` saying so, and so does the README.
- **What leaves the phone** is the same as in Phase 6, with one stricter rule and one new exposure:
  - **Stricter:** the names of the user's rooms, of DM partners and room heroes as far as they are in memory, and the user's own display name are now removed from the prompt as `[name]`, as well as Matrix IDs, links and e-mail addresses (`PromptRedactor`). It works on whole words. Screen words and common words inside a name are kept, so a contact called "Mor" still turns "mor" into `[name]`.
  - **New:** Groq now sees each phone's IP address, which the proxy used to hide.
  - Enforcement: `AssistRequest` still has no field for anything else, and `AssistChatFormat.body` is now the only code that builds the request. A test fails if anything outside the Assist tab creates a backend, or if anything but `groq_assist_backend.dart` reads `GROQ_API_KEY` or knows Groq's address.
- **Rate limits.** The free tier's limits are now shared by every study phone on the same key: about 30 requests and 8,000 tokens per minute, and 1,000 requests and 200,000 tokens per day for `openai/gpt-oss-20b`. On HTTP 429 the tab first asks the user to wait a moment. Until Groq's `retry-after` is over, the app does not ask Groq again. The on-device model answers in that time if it is set up. Another 429, or a wait over a minute (the daily quota), goes to the on-device model.
- **Malformed tool calls** (Groq's `tool_use_failed`, a call the validator cannot use, or an answer cut off without a call) are asked once more with a fixed hint. After that the user is asked to say it another way.
- **Evaluation** moved from `llm-proxy/eval/` (TypeScript) to `tool/assist_eval.dart`. It sends 33 generated requests through the app's own `GroqAssistBackend` and paces itself by tokens per minute. Run it with `flutter test tool/assist_eval.dart`.

**Not done here:** no real Groq call or evaluation run has been made. Both need a key, which is set up by hand (see the README, "AI Assist (development only)").

## Open questions

These need answers from Simon or the team. CC must not decide them.

- [ ] Which heuristics from the literature review go in, with which signals and thresholds?
- [ ] Is the emulator x86\_64 or arm64, and which real arm64 phone do we test the model on?
- [ ] Which UI elements are in scope for resizing in the first version?
- [ ] Will participants interact in Danish, English or both? This decides the test phrase list and any fine-tuning data.
- [x] Namespace string for the message metadata: `dk.aau.sw9.meaning` (decided Oct 26, 2026).
- [x] Model delivery: both. A public GitHub release, downloaded when the user taps Set up, and a study build with the model inside (decided Nov 4, 2026).
- [ ] Is the study event log covered by the ethics and consent plan as described in Phase 5? Until this is answered, logging stays off until the researcher turns it on, and the log also keeps Assist prompts (see the Phase 5 decisions).
- [ ] Phase order: is Phase 4 (metadata) needed for the first study, or can it come after?
- [ ] Ethics and consent for Phase 6: Assist prompts and the size settings now reach Groq (a US company) through our proxy, and with `STUDY_LOGGING=true` the proxy also stores the prompts on our server. Does the consent cover this?
- [ ] Mistral as a second provider: its free tier requires opting in to training on requests. Allowed once consent covers it?
- [ ] Should the study compare the online and the on-device model? That needs a third study condition that forces the on-device model.
- [ ] Which heuristics replace the placeholders in `assets/assist/heuristics.md`, and should `tools/export_app.py` in the heuristics catalog generate that file too, so the two heuristic files cannot drift?
- [ ] Ethics and consent for Phase 6b: study phones now send Assist prompts and the size settings straight to Groq, so Groq also sees each phone's IP address. Does the consent cover this?
- [ ] One shared key for all study phones, or one key per phone (more quota, but more keys to protect)? The shared free tier allows about four Assist requests per minute across all phones.
- [ ] When does the app go back to the proxy: before the study, or only before a public release?

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
