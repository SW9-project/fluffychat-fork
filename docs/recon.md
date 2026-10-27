# Phase 0: Repo reconnaissance

Date: 2026-10-26. Repo: `SW9-project/fluffychat-fork`, branch `feat/ai-personalization`, based on `main` at `93de62ac7`.
Plan: [ai-personalization-plan.md](ai-personalization-plan.md). No code was changed in this phase.

Line numbers refer to this commit and will drift.

## Read this first: the fork already has a UI restyle

`main` contains commit `bf3cd9a52` ("Initial commit / Enhanced UI", Juan Carlos López, 2026-10-26). It is a Telegram-style restyle of 32 files and touches almost every widget Phase 1 needs to change:
`lib/config/themes.dart`, `lib/pages/chat/chat_input_row.dart`, `lib/pages/chat/events/message.dart` (788 lines changed), `lib/pages/chat_list/chat_list_item.dart` (608 lines changed), `lib/widgets/avatar.dart`, `lib/widgets/theme_builder.dart`, plus a new `lib/pages/chat/chat_background.dart`.

Consequence: Phase 1 edits will conflict with any further restyle work on the same files. The team should agree who touches which file, or land the restyle first.

## 1. Versions, state management, folder structure

| Item | Value | Where |
| --- | --- | --- |
| Flutter (pinned) | 3.47.8 | `.fvmrc` |
| Flutter (installed on Simon's PC) | 3.47.7, Dart 3.13.5 | `flutter --version`. One patch behind the pin. |
| Dart SDK constraint | `>=3.11.1 <4.0.0` | `pubspec.yaml` |
| App version | 2.11.3+3574 | `pubspec.yaml` |
| Matrix SDK | `matrix` 14.1.0 | `pubspec.lock` |
| UI library | `material_ui` 1.8.0 and `cupertino_ui`, imported instead of `package:flutter/material.dart` | e.g. `lib/config/themes.dart:9`. New code should import the same way. |

**State management:** there is no central store.
- Most pages use a controller/view split: a `StatefulWidget` whose `State` is the controller, plus a stateless view that takes the controller. Example: `lib/pages/settings_style/settings_style.dart` (controller) and `settings_style_view.dart` (view).
- App-wide objects go through `provider`: `ThemeController` (`lib/widgets/theme_builder.dart`) and the `Matrix` widget (`lib/widgets/matrix.dart`).
- Newer pages use `ValueNotifier` view models through `ViewModelBuilder` (`lib/widgets/view_model_builder.dart`), e.g. `lib/pages/sign_in/view_model/`, `lib/pages/call/call_view_model.dart`.
- Routing: `go_router`, routes in `lib/config/routes.dart`.

**Folders (`lib/`):**
- `config/`: app constants (`app_config.dart`), settings (`setting_keys.dart`), theme (`themes.dart`), routes.
- `pages/<feature>/`: one folder per screen (chat, chat_list, settings_*, ...).
- `widgets/`: shared widgets (avatar, theme builder, matrix, dialogs, layouts).
- `utils/`: helpers and Matrix SDK extensions.
- `l10n/`: ARB files, including `intl_da.arb` (Danish exists).

Proposed home for our code: `lib/personalization/` (settings model, signals, heuristics, model interface), so upstream merges stay clean.

**Tests:** `test/` has a few unit and widget tests (`widget_test.dart`, `command_hint_test.dart`, ...). `integration_test/` runs against a Synapse server (`integration_test/synapse`).

## 2. Theming

- `ThemeData` is built in `FluffyThemes.buildTheme` (`lib/config/themes.dart:43`). It is called for `theme` and `darkTheme` of `MaterialApp.router` in `lib/widgets/fluffy_chat_app.dart:94-99`.
- `ThemeBuilder` (`lib/widgets/theme_builder.dart`) wraps the app. It stores theme mode and accent colour in SharedPreferences and rebuilds the `MaterialApp` through `setState`.
- No `ThemeExtension` is in use yet. Chat colours come from an `extension BubbleColorTheme on ThemeData` (`lib/config/themes.dart:197`). Adding a `ThemeExtension` in `buildTheme` would be new but fits.
- `visualDensity: VisualDensity.standard` (`themes.dart:96`).

**Text scaling already exists, partly:**
- Setting `AppSettings.fontSizeFactor` (`chat.fluffy.font_size_factor`, default 1.0) in `lib/config/setting_keys.dart:39`.
- Slider in Settings > Style, range 0.5 to 2.5, 20 steps (`lib/pages/settings_style/settings_style_view.dart:332-344`), saved in `settings_style.dart:140`.
- Applied only to the chat timeline (`lib/pages/chat/chat_event_list.dart:118`) and the input field (`lib/pages/chat/input_bar.dart:401`), by overriding `MediaQuery.textScaler`. The chat list, app bars and settings do not follow it.
- The system font size (Android accessibility setting) passes through `MediaQuery` everywhere else. Several dialogs pin their text scale back to `MediaQuery.textScalerOf(context).scale(1)`.

**Button and touch-target sizes are hard-coded constants,** with no theme-level override:
- No `materialTapTargetSize`, `minimumSize` or `tapTargetSize` anywhere in `lib/`. Flutter's default applies (`MaterialTapTargetSize.padded`, `IconButton` min 48 by 48 dp).
- Sizes in the targets are literal numbers: see point 6.
- `AppConfig.messageFontSize = 16.0` (`lib/config/app_config.dart:12`) is a `const` used for message text.

## 3. User settings: storage and adding a new one

- `enum AppSettings<T>` in `lib/config/setting_keys.dart:16`. Each entry has a SharedPreferences key and a default. Typed accessors: `.value` (synchronous read) and `.setItem(v)` (async write), via extensions for bool, String, int, double and `List<String>` (`setting_keys.dart:161-262`).
- Initialised once in `main.dart:67` (`await AppSettings.init()`), before `runApp`.
- Adding a setting means adding one enum entry, e.g. `buttonScale<double>('chat.fluffy.button_scale', 1.0)`.
- Defaults can be overridden by Android/iOS MDM managed configuration or `config.json` on web (`setting_keys.dart:98-102`, `140-157`). That gives a way to preset a study build.
- `AppSettings.reset()` removes every key.
- There is no change notification. Widgets read `.value` during `build` and only update when something else rebuilds them; the style page calls `setState`. Phase 1 needs its own `ValueNotifier`/`ChangeNotifier` on top so the whole tree rebuilds on change.
- Storage is local SharedPreferences, so it meets hard constraint 2.

**Do not use:** `applicationAccountConfig` (`lib/utils/account_config.dart`). It is stored in Matrix account data under `im.fluffychat.account_config` and syncs to the server unencrypted. The wallpaper setting lives there today.

## 4. Message send path

1. Send button `Key('send_button')` (`lib/pages/chat/chat_input_row.dart:371`) calls `ChatController.send()` (`lib/pages/chat/chat.dart:754`).
2. `send()` calls `room.sendTextEvent(text, inReplyTo:, editEventId:, parseCommands:, threadRootEventId:)` at `chat.dart:785`.
3. In the SDK (`matrix-14.1.0/lib/src/room.dart:688`), `sendTextEvent` routes plain text through `client.parseAndRunCommand` and the built-in `send` command, back into `sendTextEvent` with `parseCommands: false`.
4. `sendTextEvent` builds the content map itself (`room.dart:719`: `{'msgtype', 'body'}`, plus `m.mentions`, `format` and `formatted_body` from markdown) and passes it to the public `room.sendEvent(content, ...)` (`room.dart:1260`).

**Can extra fields be added?** Not through `sendTextEvent`: it has no parameter for extra content. Options for Phase 4, no decision made:
- (a) Build the content in FluffyChat and call `room.sendEvent(content, inReplyTo:, editEventId:, threadRootEventId:)` directly. Simple, but duplicates the SDK's markdown and mention logic (about 50 lines).
- (b) Replace the `send` command: `client.commands` is a public mutable map (`client.dart:116`, `addCommand` in `commands_extension.dart:19`). A custom `send` could add our field and call `sendEvent`. Same duplication, and it also covers other callers.
- (c) Patch or fork the SDK. Not recommended.

**Encryption is confirmed:** `sendEvent` goes to `_sendContent` (`room.dart:1211`), which encrypts the whole content with `encryptGroupMessagePayload`. Only `m.relates_to` is moved out into plaintext (`matrix-14.1.0/lib/encryption/encryption.dart:332`). A namespaced field next to `body` is encrypted, which satisfies hard constraint 3.

**Edits are confirmed:** with `editEventId`, `sendEvent` copies the full content into `m.new_content` (`room.dart:1332-1345`). Our field ends up in the replacement content automatically.

Other send paths, not text: shared items (`chat.dart:354-355`), files, location, voice, stickers, polls.

## 5. Message render path

`ChatEventList` (`lib/pages/chat/chat_event_list.dart`)
→ `Message` (`lib/pages/chat/events/message.dart:34`), which takes `event.getDisplayEvent(timeline)`. That returns the latest edit with `m.new_content` swapped in as content (SDK `event.dart:1218`).
→ `_MessageContentWithMeta` (`message.dart:997`), the bubble with time and checkmarks (`_MessageMeta`, `message.dart:1044`)
→ `MessageContent` (`lib/pages/chat/events/message_content.dart:27`); the text branch is at `:157-200`
→ `HtmlMessage` (`lib/pages/chat/events/html_message.dart`) renders the body or formatted body.

For Phase 4 the metadata can be read from `displayEvent.content['<namespace>']` in `MessageContent`'s text branch. The plain `body` stays the fallback.

## 6. Target widgets for resizing

| Target | Where | Current size |
| --- | --- | --- |
| Send button | `lib/pages/chat/chat_input_row.dart:370` (`IconButton`, key `send_button`) | Container `height` by `height` = 56 by 56 (`ChatInputRow.height`, `:26`); default icon size. The mic button shares the slot (`:339`). |
| Attach button | `chat_input_row.dart:218` (`PopupMenuButton<AddPopupMenuActions>`) | 48 wide by 56 high, animated to width 0 when `textMessageOnly` (`:213`) |
| Emoji button | `chat_input_row.dart:139` | 48 by 56 |
| Input field | `InputBar` in `chat_input_row.dart`, widget in `lib/pages/chat/input_bar.dart` | min 1, max 8 lines; text follows `fontSizeFactor` (`input_bar.dart:401`) |
| Back button | `lib/pages/chat/chat_view.dart:117` (`BackButton()`); 12 `BackButton()` uses in `lib/` in total | Flutter default, 48 dp; app bar height 56, or 72 in column mode (`themes.dart:133`) |
| Chat list items | `lib/pages/chat_list/chat_list_item.dart:84` (`ListTile`, `onTap` at `:409`) | avatar 54 (`:62`), horizontal padding 8; title and subtitle from theme text styles |
| Message bubbles | `lib/pages/chat/events/message.dart`, padding inside `message_content.dart:182` (12 by 6) | text 16 (`AppConfig.messageFontSize`) times `fontSizeFactor`; sender avatar 36 (`message.dart:135`); meta text 11 to 12 |
| Avatar (shared) | `lib/widgets/avatar.dart` | `Avatar.defaultSize = 48` |

Note: sizes are mostly `const` literals. Wiring them to settings means replacing the literals with reads from our settings object. Avoid changing `const` constructors upstream widely; prefer reading scale factors in a few spots.

## 7. Emulator ABI and arm64 device

- Only AVD on this PC: `Pixel_9_Pro_XL`, `abi.type=x86_64`, image `system-images/android-36/google_apis_playstore/x86_64` (`~/.android/avd/Pixel_9_Pro_XL.avd/config.ini`). The installed system images are x86_64 only.
- No device was connected during recon (`adb devices` was empty), so `adb shell getprop ro.product.cpu.abi` could not run. The value above comes from the AVD config.
- **This emulator cannot run the `.litertlm` engine** (hard constraint 6). The host is a Windows x86 PC, so an arm64 emulator is not an option here.
- `HOW_TO_RUN.md` and `scripts/run-ios.sh` in the fork assume macOS (`brew`). If a teammate's Mac is Apple Silicon, an arm64 Android emulator could run there. Otherwise Phase 3 needs a real arm64 phone. This is open question 2 in the plan.

## Code vs plan: things to flag

1. **`fontSizeFactor` already exists.** The plan's `textScale` overlaps it. Reuse it (keep its key so users keep their setting) or replace it? It also only covers the timeline and input today, while a global `textScale` would affect the whole app. Team decision.
2. **The UI restyle in `bf3cd9a52`** owns the same files as Phase 1 (see top).
3. **No settings change notification.** Phase 1 needs a notifier layer; the plan assumed an existing state approach.
4. **Sending custom fields needs `sendEvent`**, not `sendTextEvent` (point 4). This matters for Phase 4 only.
5. **Error reporter** (`lib/utils/error_reporter.dart`). Nothing uploads automatically. On an error it shows a dialog; **Report** opens a pre-filled GitHub issue in the browser and queries `api.github.com` with a hash of the error. Error text could include message content in theory, and the user has to click to send it. Consider hiding it in the study build (hard constraint 1).
6. **Push gateway** defaults to `push.fluffychat.im` with format `event_id_only` (`setting_keys.dart:29-36`). No message content is sent, and it is not AI-related. Noted for the ethics plan.
7. **Flutter version:** the local Flutter install (3.47.7) is one patch behind `.fvmrc` (3.47.8).
