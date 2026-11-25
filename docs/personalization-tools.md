# Functions for the fine-tuned model

The functions FunctionGemma is fine-tuned on, in English. The definitions are in
`assets/personalization_tools.json`.

## How the model sees them

- FunctionGemma's prompt template keeps only names, descriptions, string enums and
  types. It drops `minimum`, `maximum` and `default`, so the range of `steps` and every
  default are also written in the descriptions. The `default` keys in the JSON are for
  the dataset builder and the app.
- The template sorts each function's properties alphabetically, so the JSON declares
  them in that order. Every renderer then produces the same prompt.
- The model learns these exact words. Changing them means training again.

## The functions

| Function | Changes | Parameters (default) |
|---|---|---|
| `change_text_size` | Text size: all text, one kind, or one chat | `chat` name or username, `direction` bigger/smaller, `scope` everywhere/one_chat (everywhere), `size` word or number (leave out for a direction), `steps` 1–3 (2), `target` all/messages/chat_list/titles/message_input (all) |
| `change_button_size` | Icon and tap area of all buttons or one | `button` all/send/attach/emoji/microphone/back/search/menu/navigation (all), `direction` bigger/smaller, `size` word or number (leave out for a direction), `steps` 1–3 (2) |
| `change_spacing` | Space between controls | `direction` more/less, `size` word or number (leave out for a direction), `steps` 1–3 (2) |
| `change_line_spacing` | Space between lines of text | `direction` more/less, `size` word or number (leave out for a direction), `steps` 1–3 (2) |
| `set_simple_mode` | Simple view on or off | `enabled` (required) |
| `set_button_labels` | Words next to button icons | `enabled` (required) |
| `set_high_contrast` | Stronger colors and bold text | `enabled` (required) |
| `change_avatar_size` | Profile picture size | `direction` bigger/smaller, `size` word or number (leave out for a direction), `steps` 1–3 (2) |
| `set_theme` | Light, dark or follow the phone | `mode` light/dark/system (required) |
| `set_read_aloud` | Tap a message three times to hear it | `enabled` (required) |
| `set_bubble_color` | Message bubble color, everywhere or in one chat | `chat`, `color` (see below), `scope` everywhere/one_chat (everywhere), `side` mine/theirs |
| `set_app_color` | Main color of the app | `color` (see below) |
| `set_wallpaper` | Chat background, everywhere or in one chat | `chat`, `scope` everywhere/one_chat (everywhere), `wallpaper` blank/pattern/default (required) |
| `set_gesture` | A shortcut on or off | `enabled`, `gesture` swipe_to_reply/double_tap_to_react/send_on_enter/autoplay_gifs (both required) |
| `pin_chat` | Pin a chat to the top, or unpin | `chat`, `enabled` (required) |
| `mute_chat` | A chat's notifications off or on | `chat`, `enabled` (required) |
| `reset_settings` | Back to normal | `setting` all/text_size/button_size/spacing/simple_mode/button_labels/high_contrast/avatar_size/line_spacing/read_aloud (all) |
| `ask_clarification` | Asks the user to choose | `options`: the changing functions that might fit, one when only its details are unclear (required) |
| `no_action` | Nothing | none |

Every function with `size` needs a `direction` or a `size`, never both (the file lists
neither as required, so the builder checks it). `size` is `small`, `medium`, `big`,
`very_big` or a number such as `1.6`. Colors: default, red, pink, purple, indigo, blue,
cyan, teal, green, lime, yellow, amber, orange, brown, grey.

`reset_settings` with `all` does not include the theme; `set_theme(system)` does that.

## One chat

The model only notices that the user means one chat, and copies the name or username if
one was given:

- "Bigger text in the chat with Maria" → `scope: one_chat, chat: "Maria"`
- "Bigger text in this chat" → `scope: one_chat`, no `chat` (the app asks which chat)

## Size

The file is version 2 with 19 functions; the model's context is 4096 tokens. With the
19 declarations a single request is about 2,590 tokens; the training examples are 2,589
to 2,687. `training/build_dataset.py --tokenizer` measures them.

## How the app applies them

`lib/personalization/model/tool_call_interpreter.dart` turns a call into a change of
the settings in `accessibility_settings.dart`, or of an app setting
(`model/app_change.dart`, applied by `assist/assist_actions.dart`). Nothing applies
until the user taps Apply in the Assist tab, which shows the change before and after;
Undo follows. An unknown function, an unknown enum value or a missing required
argument is rejected, never guessed. `steps` (default 2) is clamped to 1–3 and every
size to its range.

`steps` 1 is one slider step, 2 one suggestion step (at least 0.2), 3 is 0.5. An
exact `size` sets the whole size instead: `small` is the minimum of that size, `medium`
1.0, `big` 1.5, `very_big` 2.0, and a number is a factor (`1.6`, `1,6`) or a
percentage (`160%`). Numbers outside 0.5–3 are rejected; the rest is clamped to the
range and snapped to its steps, so titles at `very_big` get 1.5. The Assist tab says
the size that will apply.

| Function | Setting | Steps 1 / 2 / 3 |
|---|---|---|
| `change_text_size`, `target` all / messages / chat_list / titles / message_input | Text size, or the text size of that kind on top of it | 0.1 / 0.2 / 0.5 |
| `change_text_size`, one chat | That chat's own text size, on top of the others. A name that matches exactly one chat (display name, or the username of a direct chat) is used; otherwise the app asks which chat. The chat list never reaches the model. | 0.1 / 0.2 / 0.5 |
| `change_button_size`, `button` all | Icon size and the area that reacts to a tap | 0.1 / 0.2 / 0.5 |
| `change_button_size`, one button | That button's own size, on top of the button size; its box grows with it | 0.1 / 0.2 / 0.5 |
| `change_spacing` | Spacing: Material's density from −2 to +4, the gaps in the message input row and the chat list rows | 0.25 / 0.25 / 0.5 |
| `change_line_spacing` | Space between lines of text in messages | 0.1 / 0.2 / 0.5 |
| `change_avatar_size` | Picture size | 0.1 / 0.2 / 0.5 |
| `set_button_labels` | Words under the icons of the message input buttons, the back button and the chat menu | |
| `set_high_contrast` | Bold text everywhere, secondary text and outlines as strong as the main text, stronger containers and dividers | |
| `set_read_aloud` | Tapping a message three times reads it aloud | |
| `set_theme` | FluffyChat's own light/dark setting (also in Style) | |
| `set_bubble_color` | The bubble colors of Style, everywhere or for one chat. A missing `side` or `color` is asked on the phone; a color the other side already has is refused. Changing one side keeps the other. | |
| `set_app_color` | The app color of Style; `default` is the app's own color. Undo puts back what Style showed, also the system accent color. | |
| `set_wallpaper` | The chat background of Style. `blank` is none; `default` is none everywhere, and in one chat the chat follows the app's background again. | |
| `set_gesture` | The chat settings: swipe to reply, double tap to react, send with Enter, and playing animated GIFs, stickers and emotes in the timeline (off shows their first frame) | |
| `pin_chat` | The chat is pinned to the top of the list, or unpinned | |
| `mute_chat` | The chat's notifications go to mentions only, or back to all | |
| `reset_settings` | The named setting back to normal; `all` resets every accessibility setting, not the theme | |
| `set_simple_mode`, `reset_settings(simple_mode)` | Not built yet: the app says so and changes nothing | |
| `ask_clarification` | The options as buttons; with one option, its details as quick replies (sent as English words, like the training answers). Typed text answers too. | |
| `no_action` | The app explains what it can change | |

For `pin_chat`, `mute_chat` and the one-chat functions the app finds the chat by name as
for text size, and asks which chat when none or several match.

## Conversations

`assist/assist_conversation.dart` sends the three trained shapes. The model saw one
earlier exchange, so only the last answered one is kept:

- After `ask_clarification`, the tapped function name or the typed words go back as
  `{"answer": ...}` in the same model turn.
- After Apply, the next request carries that exchange with `{"status": "applied"}`
  and `Done.`; after No thanks, a new prompt over an open proposal, or Undo, with
  `{"status": "declined"}` and `Okay, nothing changed.`
- After `no_action`, a rejected call or nothing to change, the next request starts
  fresh.

The plugin has no public way to open a conversation with earlier turns, so
`model/litert_conversation_ffi.dart` opens LiteRT-LM's conversation with the turns as
its `messages_json` preface, as the plugin's own sessions do internally.
