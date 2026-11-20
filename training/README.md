# FunctionGemma dataset

English examples for fine-tuning FunctionGemma on the functions in
`assets/personalization_tools.json` (see `docs/personalization-tools.md`).

```sh
python3 training/build_dataset.py
```

reads the hand-written examples in `source/`, checks them, and writes `data/train.jsonl`
and `data/eval.jsonl`. It needs only Python 3. With `--tokenizer` and `--template`
(FunctionGemma's `tokenizer.json` and `chat_template.jinja`, plus the `tokenizers` and
`jinja2` packages) it also renders every example with the real chat template and
reports its length in tokens.

## What is in it

2063 examples: 1910 single requests and 153 conversations. Each function has 74 to 278.
`change_text_size` has the most because it has the most combinations (text targets,
chats, directions, exact sizes). 271 examples (13.1%) end in `ask_clarification` or
`no_action`. Rendered with the 19 declarations, an example is 2589 to 2687 tokens; the
build stops above 4096.
15% of every function, separately for single requests and conversations, is held out in
`data/eval.jsonl`.

The build stops when a call does not match its declaration, or when a prompt appears
twice or with two different answers.

## Format

One JSON object per line:

```json
{"id": "change_text_size-160", "function": "change_text_size", "kind": "single",
 "messages": [
  {"role": "user", "content": "the text in my chat with peter123 is tiny"},
  {"role": "assistant", "tool_calls": [{"type": "function", "function": {
    "name": "change_text_size",
    "arguments": {"chat": "peter123", "direction": "bigger", "scope": "one_chat"}}}]}]}
```

`kind` is `single`, `answer`, `adjust` or `correct`. `function` is the function of the
last call. The functions are not repeated in every line: render the messages with
FunctionGemma's chat template and the functions from `assets/personalization_tools.json`
as `tools`. Every example ends with the call the model has to learn.

## Labelling rules

- Arguments the user did not give are left out. The build drops any argument equal to
  its default, so the model never learns to write `target: all` or `steps: 2`.
- `steps` comes only from words about the size of the change. It defaults to 2, so it is
  left out when the user says nothing about the amount. "A little", "a bit", "slightly"
  or "somewhat" is 1; "much", "quite a bit", "considerably", "a lot" or "way bigger"
  is 3. How bad the problem sounds ("way too small") does not change it. In a
  conversation, the words of the follow-up count ("a bit more" is 1).
- A size the user asks for gives `size` instead of `direction`: `small`, `medium`, `big`,
  `very_big`, or a number as written (`1.6`, `150%`, `1,4`). "Large" is `big`; "huge",
  "biggest", "maximum" or "as big as possible" is `very_big`; "tiny", "smallest",
  "minimum" or "as little as possible" is `small`. A complaint is still a direction
  ("the icons are huge" is smaller). "Normal size" is `reset_settings`, only "medium" is
  `size: medium`.
- Bubble side only when it is said: "my messages" is `mine`, "Simon's messages" or
  "other people's messages" is `theirs`; "Simon's bubbles" has no `side`. A color the
  list lacks (black, white, gold, silver, beige, turquoise) is left out. Gray is `grey`,
  violet `purple`, dark blue or navy `indigo`. Photo wallpapers, app-wide notifications
  and voice settings ("speak slower") are `no_action`.
- A named chat always gives `scope: one_chat` and the name as written, without the
  possessive ("Maria's chat" gives `Maria`). "This chat" or "one chat" gives
  `scope: one_chat` without a name.
- Taps that miss or buttons that are hard to hit: `change_button_size`. Tapping the
  wrong one because they are close together: `change_spacing`. Too many buttons:
  `set_simple_mode`. Not knowing what a button does: `set_button_labels`.
- Pale, faint or thin text: `set_high_contrast`. Small text: `change_text_size`. A too
  bright or too dark screen: `set_theme`.
- "Reset", "default", "back to normal" or "undo the changes": `reset_settings`.
- Clear about the app's look but not about what or which way: `ask_clarification`,
  with the functions that might fit, in declaration order ("the spacing" gives
  `change_spacing` and `change_line_spacing`, "change the colors" gives `set_high_contrast`,
  `set_theme`, `set_bubble_color` and `set_app_color`). One function when only its
  details are missing ("change the text size").
- Bubble and app colors, wallpaper, pin, mute, reading aloud, and the shortcuts (swipe to
  reply, double tap to react, Enter to send, GIFs playing by themselves) have their own
  functions. Leave out what the user does not say ("make the chat bubbles blue" has
  no `side`, "mute this chat" no `chat`).
- Anything else, including other app tasks, look changes no function covers (another
  font) and sentences that only use words like "big" or "bright":
  `no_action`.

## Conversations

Each conversation has one earlier exchange, in the shape the app has to send it:

- **answer**: the model called `ask_clarification`, and the user's choice comes back as
  that function's response, `{"answer": ...}`. A tapped option is the function name,
  for example `change_text_size`; typed text is the user's words. The next call
  follows in the same model turn.
- **adjust**: after an applied change, the user asks for more, less or the opposite,
  or the same change somewhere else. The earlier call gets the response
  `{"status": "applied"}` and the fixed reply `Done.`, then the user speaks again.
- **correct**: after a declined change, the user says what they meant. The response is
  `{"status": "declined"}` with the reply `Okay, nothing changed.`

The template needs a function response and a reply after every earlier call, so these
fixed texts are part of the format.

## Adding examples

Add prompts to a group in `source/<function>.json` (a group is the call plus the prompts
that should give it) or conversations to `source/multi_turn.json`, then run the build
again.
