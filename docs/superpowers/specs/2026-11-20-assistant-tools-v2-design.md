# Assistant functions v2 and the second training run

## Why

The assistant (FunctionGemma 270M, fine-tuned once, `tools1`) can only change a few sizes, the theme
and three switches, always by a relative step. Users also ask for exact sizes ("big", "1.6"),
smaller steps ("a bit bigger"), and settings the app already has but the assistant cannot reach:
line spacing, triple-tap read-aloud, bubble colors, pinning and muting a chat, the app color,
the wallpaper, accidental-gesture switches and GIF autoplay. Training again teaches the new
functions; the first model stays as it is.

## Goals

1. Exact sizes: "set the text to big", "buttons to 1.6". Small = the smallest allowed (0.8 for
   text, 1.0 for buttons, 0.5 for spacing), medium = 1.0, big = 1.5, very big = 2.0 (clamped to the
   setting's own maximum). For text, buttons, avatars, spacing and line spacing.
2. "A bit bigger" (and "a little", "slightly", "a tad", "a touch", "somewhat") changes a size by
   one slider step (0.1; 0.25 for spacing) instead of the normal 0.2. "Much" or "a lot" stays 0.5.
3. New functions: line spacing, read-aloud (triple tap), bubble color (everywhere or one chat),
   app color, wallpaper, gesture switches (swipe to reply, double tap to react, Enter to send,
   GIF autoplay), pin chat, mute chat.
4. When whose bubbles is not explicit ("Simon's message bubbles"), the app asks: my messages or
   theirs. Also asked by the app, never guessed: which chat, and the color when it is not one the
   app has.
5. The first run is kept: `training/Train1/`. The new run lives in `training/Train2/`.

## Non-goals

- No new settings beyond one switch to turn swipe-to-reply off (the app only has its direction).
- Photo wallpapers (they need a file picked), colors outside Material's primaries, app-wide
  notification settings, archiving or leaving chats.
- No change to how heuristics suggest changes.

## Anti-goals

- The app must never apply a change the user did not confirm, and must never act on an invalid
  or guessed argument. A wrong function is worse than asking.
- The new model must not get worse at the old functions (compare per function with Train1).

## Constraints

- Prompt: the 19 declarations are ~2,600 tokens (today 1,345). Training `MAX_LENGTH` and the
  phone's context go to 4096 (`convert.py` KV cache, `FunctionGemmaModel.maxTokens`, the
  integration test). The first answer on the phone takes roughly twice as long.
- Training runs on Colab (CUDA). T4 has no bf16: fp32 there, bf16 on L4/A100.
- The model learns the declarations word for word: `assets/personalization_tools.json` becomes
  version 2 and the app ships the matching `functiongemma-270M-sw9-tools2.litertlm`.

## Approaches

- **A. One function per thing (chosen).** 19 functions, ~2,600 tokens. Clearest for a 270M
  model, which already mixes up neighbours (spacing vs button size, 58%).
- B. Merge pin+mute into `set_chat_option` and app+bubble colors into `set_color`. 17 functions,
  ~2,370 tokens: only 9% shorter, and one more argument to get right.
- Training: Mac CPU (a day or more, proven stable) or Colab GPU (1–2 h). Colab chosen.

## Functions (version 2)

Changed:

- `change_text_size`, `change_button_size`, `change_spacing`, `change_avatar_size`: new optional
  `size` (string: `small`, `medium`, `big`, `very_big` or a number as written, such as `1.6` or
  `150%`). `direction` is no longer required; a call needs `direction` or `size`, and `size` wins
  when both are given. `steps` now defaults to 2: 1 = a little, left out = normal, 3 = a lot.
- `reset_settings.setting` gains `line_spacing` and `read_aloud`.
- `ask_clarification.options` lists every change function except pin and mute.

New:

| Function | Arguments | Applies |
|---|---|---|
| `change_line_spacing` | `direction` more/less, `size`, `steps` | `ScaleCategory.lineSpacing` |
| `set_read_aloud` | `enabled` | `AccessibilityToggle.tripleTapToRead` |
| `set_bubble_color` | `color`, `side` mine/theirs, `chat`, `scope` | account config or `Room.setBubbleColors` |
| `set_app_color` | `color` | `AppSettings.colorSchemeSeedInt`, `ThemeController.setPrimaryColor` |
| `set_wallpaper` | `wallpaper` blank/pattern/default, `chat`, `scope` | `setDefaultChatWallpaper` or `Room.setCustomWallpaper` |
| `set_gesture` | `gesture` swipe_to_reply/double_tap_to_react/send_on_enter/autoplay_gifs, `enabled` | `AppSettings` switches (+ new swipe switch) |
| `pin_chat` | `chat`, `enabled` | `Room.setFavourite` |
| `mute_chat` | `chat`, `enabled` | `Room.setPushRuleState` (mentions only / notify), as the chat list does |

Colors: `default` plus red, pink, purple, indigo, blue, cyan, teal, green, lime, yellow, amber,
orange, brown, grey (blue grey), the Material colors both pickers already offer. A color the
user names but the list lacks is left out, and the app shows the picker.

Draft: the function list measured above, built by a script in the plan.

## How the app handles them

- Sizes, line spacing and read-aloud are `AccessibilitySettings` changes: the existing proposal,
  preview, Apply, Undo and study log path.
- Everything else (colors, wallpaper, gestures, pin, mute) is one new result, a confirmed action:
  a sentence saying what will change, Apply / No thanks, and Undo after Apply that restores the
  previous value. The interpreter stays pure (validation only); a small executor in the Assist
  tab turns a validated call and room into apply/undo.
- Missing chat → the existing chat choice. Missing `side` → a mine/theirs choice. Missing color →
  the color picker. Already as asked → "already set".
- A bubble color equal to the other side's color is refused, as the picker does.

## Dataset (Train2)

- Starts from `training/source/` of Train1. Existing `steps` labels are converted: prompts with a
  "little" word get `steps: 1`, other default ones stay without `steps` (now 2), 2 and 3 become 3.
  Every converted prompt is reviewed by hand.
- Prompts in `no_action` and `ask_clarification` that the new functions now cover move to them
  ("make the chat bubbles blue", "mute this chat", "read my messages out loud").
- ~70–100 hand-written prompts per new function, exact-size prompts for every size function,
  contrasting pairs (line vs button spacing; bubble vs app color vs high contrast vs theme;
  "normal size" stays `reset_settings`), and conversations (answer, adjust, correct) that use the
  new functions.
- Labelling rule: a "little" word anywhere in the request gives `steps: 1`; how bad the problem
  sounds still does not change `steps`.

## Training, evaluation, conversion

- `Train1/` gets today's `output/` and `data/`, plus copies of the v1 function file and
  `source/`, so it is complete on its own. Its `.litertlm` moves there from `assets/models/` when
  `tools2` replaces it, so the app does not ship both.
- Scripts default to `Train2/`. `train.py`: `MAX_LENGTH` 4096, bf16 only where the GPU supports it.
  A Colab notebook runs training and evaluation on the GPU; the trained folder comes back to the
  Mac for `convert.py` (KV cache 4096) and the on-device test.
- `evaluate.py` reports per function, as before; the new model is compared with Train1 on the old
  functions.

## Left to the builder

Exact wording of descriptions (within the measured budget), the prompts themselves, English and
Danish strings for the new confirmations and choices, and test coverage.
