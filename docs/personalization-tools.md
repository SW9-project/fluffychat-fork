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
| `change_text_size` | Text size: all text, one kind, or one chat | `chat` name or username, `direction` bigger/smaller (required), `scope` everywhere/one_chat (everywhere), `steps` 1–3 (1), `target` all/messages/chat_list/titles/message_input (all) |
| `change_button_size` | Icon and tap area of all buttons or one | `button` all/send/attach/emoji/microphone/back/search/menu/navigation (all), `direction` bigger/smaller (required), `steps` 1–3 (1) |
| `change_spacing` | Space between controls | `direction` more/less (required), `steps` 1–3 (1) |
| `set_simple_mode` | Simple view on or off | `enabled` (required) |
| `set_button_labels` | Words next to button icons | `enabled` (required) |
| `set_high_contrast` | Stronger colors and bold text | `enabled` (required) |
| `change_avatar_size` | Profile picture size | `direction` bigger/smaller (required), `steps` 1–3 (1) |
| `set_theme` | Light, dark or follow the phone | `mode` light/dark/system (required) |
| `reset_settings` | Back to normal | `setting` all/text_size/button_size/spacing/simple_mode/button_labels/high_contrast/avatar_size (all) |
| `ask_clarification` | Asks the user to choose | `options`: the functions that might fit, one when only its details are unclear (required) |
| `no_action` | Nothing | none |

`reset_settings` with `all` does not include the theme; `set_theme(system)` does that.

## One chat

The model only notices that the user means one chat, and copies the name or username if
one was given:

- "Bigger text in the chat with Maria" → `scope: one_chat, chat: "Maria"`
- "Bigger text in this chat" → `scope: one_chat`, no `chat` (the app asks which chat)

## Size

Rendered with FunctionGemma's template and counted with its tokenizer, the eleven
functions plus a 15-word request take 1364 tokens. The template structure alone (names,
enums, types) is 852 of them.

## How the app applies them

`lib/personalization/model/tool_call_interpreter.dart` turns a call into a change of
the settings in `accessibility_settings.dart`. Nothing applies until the user taps
Apply in the Assist tab, which shows the change before and after; Undo follows. An
unknown function, an unknown enum value or a missing required argument is rejected,
never guessed. `steps` is clamped to 1–3 and every size to its range.

| Function | Setting | One step |
|---|---|---|
| `change_text_size`, `target` all / messages / chat_list / titles / message_input | Text size, or the text size of that kind on top of it | 0.1× |
| `change_text_size`, one chat | That chat's own text size, on top of the others. A name that matches exactly one chat (display name, or the username of a direct chat) is used; otherwise the app asks which chat. The chat list never reaches the model. | 0.1× |
| `change_button_size`, `button` all | Icon size and the area that reacts to a tap | 0.1× |
| `change_button_size`, one button | That button's own size, on top of the button size; its box grows with it | 0.1× |
| `change_spacing` | Spacing: Material's density from −2 to +4, the gaps in the message input row and the chat list rows | 0.25× |
| `change_avatar_size` | Picture size | 0.1× |
| `set_button_labels` | Words under the icons of the message input buttons, the back button and the chat menu | |
| `set_high_contrast` | Bold text everywhere, secondary text and outlines as strong as the main text, stronger containers and dividers | |
| `set_theme` | FluffyChat's own light/dark setting (also in Style) | |
| `reset_settings` | The named setting back to normal; `all` resets every accessibility setting, not the theme | |
| `set_simple_mode`, `reset_settings(simple_mode)` | Not built yet: the app says so and changes nothing | |
| `ask_clarification` | The options as buttons; with one option, its details as quick replies (sent as English words, like the training answers). Typed text answers too. | |
| `no_action` | The app explains what it can change | |

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
