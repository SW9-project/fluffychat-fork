# Assistant functions v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach the on-device assistant 8 new functions, exact sizes and small steps, train it again in `training/Train2/` on Colab, and keep the first model in `training/Train1/`.

**Architecture:** `assets/personalization_tools.json` v2 is the single contract: the dataset builder checks examples against it, and the app's `ToolCallInterpreter` validates calls against it. Size, line-spacing and read-aloud calls reuse the existing `SettingsChange` proposal path. Colors, wallpaper, gestures, pin and mute become an `AppChange` that the Assist tab applies through a small `AssistActions` interface backed by the Matrix client.

**Tech Stack:** Flutter/Dart (matrix SDK, flutter_test), Python 3.12 (transformers 5.22.2, trl 1.17.1, datasets 5.1.0, accelerate 1.15.0, torch 2.15 locally / Colab's own CUDA torch), litert-torch for conversion.

**Spec:** `docs/superpowers/specs/2026-11-20-assistant-tools-v2-design.md`

## Global Constraints

- The function file is the contract: names, descriptions and enum values exactly as in Task 2; properties in alphabetical order; `version: 2`.
- Sizes: small = the category's `min`, medium = 1.0, big = 1.5, very_big = 2.0, every value clamped to the category's range.
- `steps`: default 2. 1 → the category's slider `step` (0.1; 0.25 for spacing), 2 → `suggestionStep` (0.2; 0.25 for spacing), 3 → 0.5.
- Colors: `default`, red, pink, purple, indigo, blue, cyan, teal, green, lime, yellow, amber, orange, brown, grey → `null`, `Colors.red` … `Colors.brown`, `Colors.blueGrey`.
- Context: `MAX_LENGTH` (train.py) = 4096, `KV_CACHE` (convert.py) = 4096, `FunctionGemmaModel.maxTokens` = 4096.
- Model id `functiongemma-270M-sw9-tools2`. Train1 is never deleted or overwritten.
- Never apply an unconfirmed change, and never guess a missing chat, side or color.
- No chat names or room ids in the study log.
- User-facing strings in English and Danish (`AppearanceL10n`, `PersonalizationL10n`). Words sent to the model stay English.
- The "Commit" steps run only once the user asks for commits (the tree has unrelated uncommitted work on `main`); until then, skip them.

## Review Focus

1. Model writes `size` loosely ("Big", " big ", "1,6", "160 %", "1.60"): trimmed, case-insensitive, comma read as a decimal point, `%` divides by 100. Pinned in Task 3.
2. Both `direction` and `size`: `size` wins; neither: invalid, never a guessed direction. Pinned in Task 3.
3. A bubble color equal to the other side's current color: refused with a clear sentence, not applied. Pinned in Task 4.
4. A pin/mute name that matches several chats or none: the existing chat chooser, never the first match. Pinned in Task 4.
5. Any rendered example over 4096 tokens (long conversations with 19 declarations): the build stops. Pinned in Task 6.

---

### Task 1: Archive Train1 and point the scripts at Train2

**Files:**
- Move: `training/output/` → `training/Train1/output/`, `training/data/` → `training/Train1/data/`
- Copy: `assets/personalization_tools.json` → `training/Train1/personalization_tools.json`, `training/source/` → `training/Train1/source/`
- Modify: `training/build_dataset.py` (`OUT_DIR`), `training/render_dataset.py` (`DATA_DIR`), `training/train.py` (`DATA_DIR`, `OUT_DIR`, `MAX_LENGTH`, bf16), `training/evaluate.py` (`DATA_DIR`, `OUT_DIR`, `MODELS`), `training/export_eval_cases.py` (data paths), `training/convert.py` (`DEFAULT_CHECKPOINT`, `DEFAULT_NAME`, `KV_CACHE`, workdir), `.gitignore`
- Create: `training/Train1/README.md` (5 lines: what it is, date, epoch 7, results table pointer to TRAINING.md)

**Interfaces:**
- Produces: `training/Train2/data/` and `training/Train2/output/functiongemma/` as the defaults of every script; `evaluate.py --models base,train2`.

- [ ] **Step 1:** `git mv training/data training/Train1/data`, plain `mv training/output training/Train1/output` (ignored), copy the function file and `source/`.
- [ ] **Step 2:** Set paths: `RUN = HERE / "Train2"`, data `RUN / "data"`, model `RUN / "output" / "functiongemma"`; `MODELS = {"base": …, "train2": RUN / "output" / "functiongemma"}`; convert `DEFAULT_NAME = "functiongemma-270M-sw9-tools2"`, `KV_CACHE = 4096`. In train.py: `MAX_LENGTH = 4096`, `bf16 = device == "cuda" and torch.cuda.is_bf16_supported()`, model dtype bf16 only then (fp32 otherwise, e.g. a T4).
- [ ] **Step 3:** `.gitignore`: replace `training/output/` with `training/Train*/output/`.
- [ ] **Step 4: Verify** `python3 training/build_dataset.py` (still v1 tools) writes `training/Train2/data/train.jsonl`, and `diff training/Train1/data/train.jsonl training/Train2/data/train.jsonl` prints nothing. Then `rm -r training/Train2/data` (Task 6 rebuilds it). `ls training/Train1/output/functiongemma-pilot/model.safetensors` exists.
- [ ] **Step 5: Commit** `chore(training): keep the first run in Train1, new runs in Train2`

### Task 2: Function file v2 and the builder's checks

**Files:**
- Modify: `assets/personalization_tools.json`, `training/build_dataset.py` (`normalize_call`, `NEGATIVE` unchanged), `lib/personalization/model/personalization_tools.dart`, `test/personalization/personalization_tools_test.dart`, `docs/personalization-tools.md`

**Interfaces:**
- Produces, in this order (19): `change_text_size`, `change_button_size`, `change_spacing`, `change_line_spacing`, `set_simple_mode`, `set_button_labels`, `set_high_contrast`, `change_avatar_size`, `set_theme`, `set_read_aloud`, `set_bubble_color`, `set_app_color`, `set_wallpaper`, `set_gesture`, `pin_chat`, `mute_chat`, `reset_settings`, `ask_clarification`, `no_action`.
- Dart constants: `changeLineSpacing`, `setReadAloud`, `setBubbleColor`, `setAppColor`, `setWallpaper`, `setGesture`, `pinChat`, `muteChat`; `changeFunctions` = every function except `pinChat`, `muteChat`, `askClarification`, `noAction`, in file order; `static const sizeWords = ['small', 'medium', 'big', 'very_big']`; `static const colors = [...]` (Global Constraints order).

- [ ] **Step 1:** Generate the file with the scratchpad draft builder (`tools_v2_draft.json` from the brainstorm). Copy every v1 description unchanged except where listed:
  - `steps`: `{"type":"integer","minimum":1,"maximum":3,"default":2,"description":"1 is a little, 3 is a lot. Leave out if not said."}`
  - `size` (in the four `change_*_size`/`change_spacing` and `change_line_spacing`): `{"type":"string","description":"Exact size: small, medium, big, very_big or a number like 1.6. Leave out for bigger or smaller."}`
  - `required: []` for every function with `size`.
  - New functions, descriptions verbatim:
    - `change_line_spacing`: "Put more or less space between lines of text. Use when lines are cramped or too far apart." `direction` enum more/less "more if cramped, less if too far apart."
    - `set_read_aloud`: "Turn reading aloud on or off: tapping a message three times reads it out. Use when reading is hard or the user wants to hear messages." `enabled` required.
    - `set_bubble_color`: "Change the color of message bubbles, everywhere or in one chat." `chat`, `scope` as in `change_text_size`; `color` enum (Global Constraints) "default for the normal color. Leave out if not one of these."; `side` enum mine/theirs "Whose messages. Leave out if not clear."
    - `set_app_color`: "Change the main color of the app." `color` as above.
    - `set_wallpaper`: "Change the chat background, everywhere or in one chat." `wallpaper` enum blank/pattern/default "blank for none, default for the normal one." (required), `chat`, `scope`.
    - `set_gesture`: "Turn a shortcut on or off: swipe to reply, double tap to react, Enter to send, or playing GIFs by themselves. Use when it happens by accident." `gesture` enum swipe_to_reply/double_tap_to_react/send_on_enter/autoplay_gifs "Which one.", `enabled`; both required.
    - `pin_chat`: "Pin a chat to the top of the chat list, or unpin it." `chat`, `enabled` "true to pin, false to unpin." (required).
    - `mute_chat`: "Turn a chat's notifications off or on again." `chat`, `enabled` "true to mute, false to unmute." (required).
  - `reset_settings.setting` enum gains `line_spacing`, `read_aloud`. `ask_clarification.options` enum = `changeFunctions`.
- [ ] **Step 2: Builder.** `normalize_call` accepts `size` only as one of the size words or a number string matching `^\d+([.,]\d+)?\s*%?$`; raises `BuildError` otherwise. A call to a `change_*`/`change_line_spacing` function needs `direction` or `size` (raise "needs direction or size"), never both. Chat rule extended: `chat` without `scope: one_chat` is an error only for functions that have `scope`.
- [ ] **Step 3: Tests.** Update `personalization_tools_test.dart`: the order test expects the 19 names above; `rangeOf('change_spacing','steps') == (1, 3)`, `defaultOf('change_text_size','steps') == 2`, `requiredOf('change_text_size')` is empty, `requiredOf('set_gesture')` is `['enabled','gesture']`. Add `test('the new chat functions name their chat like text size does')`: `enumOf('set_bubble_color','scope') == ['everywhere','one_chat']`.
- [ ] **Step 4: Run** `flutter test test/personalization/personalization_tools_test.dart`. Expected: all pass except `every function has training examples`, which fails until Task 6 (note it in the commit message).
- [ ] **Step 5:** Update `docs/personalization-tools.md` (function table, sizes, steps, version 2, 4096 context). **Commit** `feat(assistant): function file v2`

### Task 3: Interpreter: sizes, steps and the new functions

**Files:**
- Modify: `lib/personalization/model/tool_call_interpreter.dart`
- Create: `lib/personalization/model/app_change.dart`
- Test: `test/personalization/tool_call_interpreter_test.dart`

**Interfaces:**
- Consumes: Task 2 constants.
- Produces:
  - `enum AppSetting { ownBubbleColor, otherBubbleColor, appColor, wallpaper, swipeToReply, doubleTapToReact, sendOnEnter, autoplayGifs, pinned, muted }`
  - `class AppChange { final AppSetting setting; final String? roomId; final Object? value; }`, where `value` is an `int?` ARGB for colors (null = default), a `String?` for wallpaper (`'none'`, `'pattern'`, null = default for the chat), and a `bool` otherwise. Equality is by fields.
  - `class AssistAppProposal extends AssistResult { final ProposedCall call; final AppChange change; }`
  - `class AssistNeedsDetail extends AssistResult { final ProposedCall call; final String parameter; final List<String> options; final String? roomId; }`, with `parameter` `'side'` (options `['mine','theirs']`) or `'color'` (options `PersonalizationTools.colors` without `default`).
  - `AssistResult interpret(ProposedCall? call, {String? roomId})` and `AssistResult forChat(ProposedCall call, String roomId)` (text size as today, every other chat function → `interpret(call, roomId: roomId)`).
  - `ProposedCall withArg(String key, Object? value)` on `ProposedCall` (settings_intent_model.dart).
  - `static Color? colorOf(String name)` on `ToolCallInterpreter`.

- [ ] **Step 1: Failing tests** (add to the existing groups):
  - `steps: 1 is one slider step, left out is the suggestion step, 3 is 0.5`: text bigger with steps 1 → 1.1, none → 1.2, 3 → 1.5; spacing more with steps 1 → 1.25.
  - `size words: small is the minimum, medium 1.0, big 1.5, very_big 2.0`: text `small` → 0.8, buttons `small` → button 1.0, text `very_big` with target `titles` → 1.5 (clamped), `medium` from 1.4 → 1.0.
  - `size numbers as the model writes them`: `'1.6'`, `' 1,6 '`, `'160%'`, `'160 %'`, `'Big'` → 1.6/1.6/1.6/1.6/1.5 text scale; `'5'`, `'abc'`, `''` → `AssistNoSuggestion(invalidArguments)`.
  - `size wins over direction; neither is invalid`.
  - `one chat with a size sets that chat's whole message size`: `forChat(change_text_size {size: big, scope: one_chat}, '!a')` → `messageScale('!a') == 1.5`.
  - `line spacing and read aloud use the settings`: `change_line_spacing more` → `lineSpacing` 1.2; `less` at 1.0 → `AssistUnchanged(atLimit)`; `set_read_aloud true` → `tripleTapToRead` on; reset `line_spacing`/`read_aloud` reset only those.
  - `chat functions ask which chat first`: `pin_chat {enabled: true}` and `set_bubble_color {color: red, side: mine, scope: one_chat}` → `AssistNeedsChat`; with `roomId: '!a'` → `AssistAppProposal(AppChange(pinned, '!a', true))` and `AppChange(ownBubbleColor, '!a', Colors.red.toARGB32())`.
  - `bubble color asks side, then color`: no `side` → `AssistNeedsDetail(parameter: 'side')`; side given, no color → `parameter: 'color'`; everywhere without chat → no `AssistNeedsChat`.
  - `app color, wallpaper and gestures`: `set_app_color default` → `AppChange(appColor, null, null)`; `set_wallpaper blank` → `AppChange(wallpaper, null, 'none')`; `set_wallpaper default` everywhere → value `'none'`, one chat → null; `set_gesture {gesture: autoplay_gifs, enabled: false}` → `AppChange(autoplayGifs, null, false)`; unknown gesture → invalid.
  - `mute false is unmute` → `AppChange(muted, '!a', false)`.
- [ ] **Step 2: Run** `flutter test test/personalization/tool_call_interpreter_test.dart`. Expected: the new tests fail (missing types), and the old `steps are clamped` test fails on its 1-step value. Update that test to the new amounts.
- [ ] **Step 3: Implement.** `_amount`: `{1: category.step, 2: category.suggestionStep, 3: 0.5}` after clamping. `_size(call, category) → double?` parses as in Review Focus 1 (word → value, number ≤ 3 is a factor, `%` divides by 100, result outside 0.5–3 → `_Invalid`). `_scale` sets `withEffective(c, size ?? current + sign * amount)` and needs `direction` only when `size` is null. The interpreter never reads room state: "already set" is decided in Task 4.
- [ ] **Step 4: Run** the same test file. Expected: PASS. Also run `flutter test test/personalization/` to catch other users of `forChat`/`interpret`, and fix call sites (`AssistAnswered` study event: add `AssistAppProposal() => 'assist_app_proposal'` and `AssistNeedsDetail() => 'assist_needs_detail'`, logging the call and `change.setting.name`, never `roomId`).
- [ ] **Step 5: Commit** `feat(assistant): interpret exact sizes, small steps and the new functions`

### Task 4: Assist tab applies app changes

**Files:**
- Create: `lib/personalization/assist/assist_actions.dart` (interface + `MatrixAssistActions`)
- Modify: `lib/personalization/assist/assist_view.dart`, `lib/pages/assistant/assistant_page.dart`, `lib/personalization/appearance_l10n.dart`, `lib/personalization/study/study_events.dart`, `lib/config/setting_keys.dart`, `lib/pages/chat/events/message.dart`, `lib/pages/settings_chat/settings_chat_view.dart`, `lib/l10n/intl_en.arb` (+ `flutter gen-l10n`)
- Test: `test/personalization/assist_view_test.dart`

**Interfaces:**
- Consumes: Task 3 `AppChange`, `AppSetting`, `AssistAppProposal`, `AssistNeedsDetail`, `forChat`, `withArg`.
- Produces:
  - `abstract class AssistActions { Object? current(AppSetting setting, String? roomId); Future<void> apply(AppChange change); }`
  - `MatrixAssistActions(Client client, void Function(Color?) setPrimaryColor)`. It maps:
    - colors to `setBubbleColors`/`setApplicationAccountConfig`, keeping the other side;
    - the app color to `AppSettings.colorSchemeSeedInt` plus `setPrimaryColor`;
    - wallpaper to `setDefaultChatWallpaper`/`setCustomWallpaper`;
    - gestures to the `AppSettings` switches;
    - pin to `setFavourite`, mute to `setPushRuleState(mentionsOnly | notify)`.
  - `AppSettings.swipeToReply<bool>('chat.fluffy.swipe_to_reply', true)`.
  - `AssistView.actions` (required `AssistActions`).
  - `UnchangedReason.sameAsOtherSide`.

- [ ] **Step 1: Failing widget tests** with a `_FakeActions` that records `apply` and returns values from a map:
  - `pin: a named chat applies after Apply and undoes to the old value` (model returns `pin_chat {chat: Simon, enabled: true}`, chats contain one "Simon"; tap `assist_apply`; `_FakeActions.applied == [AppChange(pinned, '!simon', true)]`; tap `assist_undo` → `AppChange(pinned, '!simon', false)`).
  - `two chats called Simon show the chooser, not the first` (Review Focus 4).
  - `bubble side unclear asks mine or theirs` (keys `assist_detail_mine`, `assist_detail_theirs`; choosing `theirs` shows a proposal for `otherBubbleColor`).
  - `a color the other side already has is refused` (`current(otherBubbleColor) == red` → text `words.sameAsOtherSide`, no `assist_apply`) (Review Focus 3).
  - `already pinned says already set`.
  - `exact text size proposal says the size` (`change_text_size {size: '1.6'}` → text "Set all text to 1.6?").
- [ ] **Step 2: Run** `flutter test test/personalization/assist_view_test.dart`. Expected: new tests FAIL.
- [ ] **Step 3: Implement.**
  - `_Exchange` gains `roomId` and `appFrom`.
  - `_resolveChat` and `_chooseChat` use the generalized `forChat`.
  - `AssistNeedsDetail` renders chips with keys `assist_detail_<option>`. A tap re-runs `interpret(call.withArg(parameter, option), roomId: exchange.roomId)` without asking the model again.
  - `AssistAppProposal` renders `words.appChange(change, chatName)`, then No thanks / Apply, then Undo after Apply. Apply stores `appFrom = actions.current(...)` and applies. Undo applies `AppChange(setting, roomId, appFrom)`.
  - Before showing a proposal: if `current == value`, show `alreadySet`; for own or other bubble colors equal to the other side's current color, show `sameAsOtherSide`.
  - `_conversation.resolved(applied: …)` as for settings proposals.
  - Study events: `AssistAppChangeEvent(String setting, String action)`, where `action` is apply/decline/undo.
- [ ] **Step 4: Strings (en + da).**
  - `functionTitles` for the six new change functions: Line spacing, Read aloud, Bubble color, App color, Chat background, Gestures.
  - `quickReplies`: `change_line_spacing` → `['more space', 'less space']`, `set_read_aloud` → `['on', 'off']`, `set_wallpaper` → `['blank', 'pattern']`, others empty.
  - `sizeTo(String what, String size)` → "Set $what to $size?". Size words are shown as Small/Medium/Big/Very big, numbers as written.
  - `lineSpacing(bool more)`.
  - `appChange(AppChange, String? chat)`, e.g. "Pin the chat with $chat?", "Mute the chat with $chat?", "Make your bubbles in the chat with $chat red?", "Make the app green?", "Use a blank background in all chats?", "Turn off playing GIFs by themselves?".
  - `sameAsOtherSide` → "The other side already has that color, so the bubbles would look the same. Pick another color."
  - Update `noAction` to list the new abilities.
- [ ] **Step 5: Swipe switch.** In `message.dart`, wrap with `SwipeToReply` only when `AppSettings.swipeToReply.value`. Add a `SettingsSwitchListTile` above the direction switch, using the new arb key `swipeToReply` "Swipe to reply". Run `flutter gen-l10n`.
- [ ] **Step 6:** In `assistant_page.dart`, pass `actions: MatrixAssistActions(Matrix.of(context).client, ThemeController.of(context).setPrimaryColor)`.
- [ ] **Step 7: Run** `flutter test test/personalization/` and `flutter analyze lib test`. Expected: all pass (except the training-examples test until Task 6), no analyzer issues.
- [ ] **Step 8: Commit** `feat(assistant): apply colors, wallpaper, gestures, pin and mute`

### Task 5: Convert the existing examples

**Files:**
- Modify: every file in `training/source/`
- Temporary: `<scratchpad>/relabel_steps.py` (not committed)

- [ ] **Step 1: Relabel steps** with the scratch script, for every group of the size and spacing functions:
  - default steps (old 1) plus a prompt matching `\b(a (little|bit|tad|touch)|slightly|somewhat|little bit)\b` → `steps: 1`;
  - default steps without that match → no `steps`;
  - steps 2 or 3 → `steps: 3`.
  - Split groups where prompts diverge, and print every changed prompt.
- [ ] **Step 2: Review** the printed list by hand. Fix by hand every prompt where "a bit" describes something other than the size of the change. Rule: a "little" word anywhere gives `steps: 1`, so only fix false regex hits ("I'm a bit lost").
- [ ] **Step 3: Move covered prompts.** From `no_action.json`, move to the new functions:
  - "make the chat bubbles blue" → `set_bubble_color {color: blue}` (no side: the app asks);
  - "mute this chat" → `mute_chat {enabled: true}`;
  - "read my messages out loud" → `set_read_aloud {enabled: true}`;
  - and every other prompt about bubbles, wallpaper, pin, mute, GIFs, swipe, Enter or app color.
  - "turn off notifications" stays `no_action` (app-wide).
  - Re-check `ask_clarification.json` options: add new functions where they fit ("the spacing" → `[change_spacing, change_line_spacing]`; "change the colors" → `[set_high_contrast, set_theme, set_bubble_color, set_app_color]`).
- [ ] **Step 4: Verify** `python3 training/build_dataset.py` stops only on the missing new-function minimums (report flags `< minimum`), not on schema errors.
- [ ] **Step 5: Commit** `data(training): steps and moved prompts for v2`

### Task 6: Examples for the new functions and exact sizes

**Files:**
- Create: `training/source/{change_line_spacing,set_read_aloud,set_bubble_color,set_app_color,set_wallpaper,set_gesture,pin_chat,mute_chat}.json`
- Modify: `training/source/{change_text_size,change_button_size,change_spacing,change_avatar_size,multi_turn,no_action,ask_clarification}.json`, `training/build_dataset.py` (token check)

- [ ] **Step 1: Token check.** `token_report` raises `BuildError` when an example exceeds `MAX_TOKENS = 4096` (Review Focus 5).
- [ ] **Step 2: Write prompts** (hand-written, varied register, typos and spoken style as in v1):

  | Target | Count | Must include |
  |---|---|---|
  | Per new function | ≥ 70 | on/off and both directions; chats named with spaces, dots, possessives ("Simon's chat" → `Simon`) |
  | Sizes | ≥ 25 per size function | the four words with synonyms (large → big; huge/biggest/maximum → very_big; tiny/smallest → small); numbers "1.6", "2", "150%"; chat and one-button variants |
  | Contrast pairs | ≥ 15 each | line spacing vs button spacing; bubble vs app color vs high contrast vs theme; "normal size" → `reset_settings` vs "medium" → size; "read this to me" → `set_read_aloud` vs "speak slower" → `no_action` |
  | Bubble side | mixed | explicit mine/theirs ("Simon's messages" → theirs, "my bubbles" → mine), and unclear ("Simon's bubbles", "the bubbles in Simon's chat") without `side` |
  | Unsupported colors | a few | black, white, gold → no `color` |
  | Conversations | ≥ 4 per new function | answer, adjust ("a bit more"), correct ("no, unpin it") |

- [ ] **Step 3: Verify** with `training/.venv/bin/python training/build_dataset.py --tokenizer training/functiongemma-270m-it/tokenizer.json --template training/functiongemma-270m-it/chat_template.jinja`. Expected:
  - no `< minimum`;
  - negatives 12–18%;
  - max tokens < 4096.
- [ ] **Step 4:** `flutter test test/personalization/personalization_tools_test.dart`. Expected: all pass.
- [ ] **Step 5: Commit** `data(training): examples for the v2 functions`

### Task 7: Render, smoke-train and package for Colab

**Files:**
- Create: `training/colab_train.ipynb`, `training/pack_colab.sh`
- Modify: `training/README.md`, `training/TRAINING.md` (Train1/Train2 section, Colab steps, new lengths)

- [ ] **Step 1:** `training/.venv/bin/python training/render_dataset.py`, then `training/.venv/bin/python training/train.py --max-steps 2 --output <scratchpad>/smoke`. Expected: both finish; train prints the example counts and two loss lines.
- [ ] **Step 2:** `pack_colab.sh` zips, keeping repo-relative paths:
  - `training/{train.py,evaluate.py,build_dataset.py}`
  - `training/functiongemma-270m-it/`
  - `training/Train2/data/`
  - `assets/personalization_tools.json`

  It writes `<repo>/training/Train2/colab.zip`.
- [ ] **Step 3:** The notebook cells are:
  - mount Drive;
  - unzip `MyDrive/colab.zip` to `/content/fc`;
  - `pip install transformers==5.22.2 trl==1.17.1 datasets==5.1.0 accelerate==1.15.0` (keep Colab's torch);
  - `!nvidia-smi`;
  - `python training/train.py`;
  - `python training/evaluate.py --models base,train2`;
  - zip `training/Train2/output/functiongemma` and the eval files back to `MyDrive/train2_result.zip`.
- [ ] **Step 4: Commit** `chore(training): Colab notebook for Train2`
- [ ] **Step 5: Hand-off:** the user uploads `colab.zip` to Drive and runs the notebook. **Wait for `train2_result.zip`.**

### Task 8: Evaluate, convert and ship tools2 (after the Colab run)

**Files:**
- Modify: `training/TRAINING.md` (Train2 results), `assets/models/model.json`, `assets/models/README.md`, `lib/personalization/model/assistant_model_config.dart` (`id`), `lib/personalization/model/function_gemma_model.dart` (`maxTokens = 4096`), `integration_test/personalization_eval_cases.dart` (via `export_eval_cases.py`)
- Move: `assets/models/functiongemma-270M-sw9-tools1.litertlm` → `training/Train1/`

- [ ] **Step 1:** Unzip the result into `training/Train2/output/`. Compare per function with Train1's table: on the old 11 functions, no function may drop more than 10 points in function accuracy. Record the results in TRAINING.md.
- [ ] **Step 2:** `training/.convert-venv/bin/python training/convert.py` writes `assets/models/functiongemma-270M-sw9-tools2.litertlm`. Update `model.json` (sha256 from `shasum -a 256`, size, source line) and the config id.
- [ ] **Step 3:** `training/.venv/bin/python training/export_eval_cases.py`, then `flutter test test/personalization/assistant_model_config_test.dart`, then the on-device `integration_test/personalization_model_test.dart` on a real arm64 phone (see the memory note on simulators). Record accuracy and latency.
- [ ] **Step 4: Commit** `feat(assistant): ship functiongemma tools2`
