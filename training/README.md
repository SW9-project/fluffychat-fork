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

1050 examples: 958 single requests and 92 conversations. Each function has 70 to 221.
`change_text_size` has the most because it has the most combinations (text targets,
chats, directions). 154 examples (14.7%) end in `ask_clarification` or `no_action`.
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
  its default, so the model never learns to write `target: all` or `steps: 1`.
- `steps` comes only from words about the size of the change: none, "a little" or "a
  bit" is 1, "much", "quite a bit" or "considerably" is 2, "a lot", "way bigger", "huge"
  or "as big as possible" is 3. How bad the problem sounds ("way too small") does not
  change it.
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
  with the functions that might fit, in declaration order. One function when only its
  details are missing ("change the text size").
- Anything else, including other app tasks, look changes no function covers (another
  font, colored bubbles) and sentences that only use words like "big" or "bright":
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
