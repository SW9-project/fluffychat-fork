<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

<img src="https://raw.githubusercontent.com/krille-chan/fluffychat/refs/heads/main/assets/logo/img/banner.png">

[FluffyChat](https://fluffychat.im) is an open source, nonprofit and cute [[matrix](https://matrix.org)] client written in [Flutter](https://flutter.dev). The goal of the app is to create an easy to use instant messenger which is open source and accessible for everyone.

### Links:

- 🌐 [[Weblate] Translate FluffyChat into your language](https://hosted.weblate.org/projects/fluffychat/)
- 🌍 [[m] Join the community](https://matrix.to/#/#fluffy-space:matrix.org)
- 📰 [[Mastodon] Get updates on social media](https://troet.cafe/@krille)
- 💝 [[Liberapay] Support FluffyChat development](https://de.liberapay.com/KrilleChritzelius)

<a href='https://ko-fi.com/krille' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi5.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

### Screenshots:

<img src="https://github.com/krille-chan/fluffychat-website/blob/main/public/img/screenshot_mobile.png?raw=true" height="300">
<img src="https://github.com/krille-chan/fluffychat-website/blob/main/public/img/screenshot_desktop.png?raw=true" height="300">

# Features

- 📩 Send all kinds of messages, images and files
- 🤙 Video calls with Matrix RTC
- 🎙️ Voice messages
- 📍 Location sharing
- 🔔 Push notifications
- 💬 Unlimited private and public group chats
- 📣 Public channels with thousands of participants
- 🛠️ Feature rich group moderation including all matrix features
- 🔍 Discover and join public groups
- 🎨 Material You design
- 😄 Custom emotes and stickers
- 🌌 Spaces
- 🔐 End to end encryption
- 🔒 Encrypted chat backup
- 😀 Emoji verification & cross signing
... and much more.


# Installation

Please visit the website for installation instructions:

- https://fluffychat.im

# Configuration and Mobile Device Management (MDM)

FluffyChat supports configuration via MDM on Android&iOS (since v2.10.0) and via a config.json file on web. You can see the populated configuration for MDM on Android in this file under `/android/app/src/main/res/xml/app_restrictions.xml`.
An example configuration can be found in the `config.sample.json` file.

# How to build

1. To build FluffyChat you need [Flutter](https://flutter.dev) and [Rust](https://www.rust-lang.org/tools/install)

2. Clone the repo:
```
git clone https://github.com/krille-chan/fluffychat.git
cd fluffychat
```
3. Debug on your platform with: `flutter run`

### Web

* Execute once before run or build:
```bash
./scripts/prepare-web.sh # To install Vodozemac
```

* Optionally configure by serving a `config.json` at the same path as fluffychat.
  An example can be found at `config.sample.json`. All values there are optional.
  **Please only the values, you really need**. If you e.g. only want
  to change the default homeserver, then only modify the `defaultHomeserver` key.

## How to run integration tests

You need to have docker installed locally! Run the preparation script before every test run:

```sh
./scripts/prepare_integration_test.sh
```

Then run all tests with:

```sh
flutter test integration_test/mobile_test.dart
```


# AI Assist (development only)

> [!WARNING]
> **Dev-only setup. Replace it with a proxy before any public release.**
> The Assist tab calls Groq directly with an API key that is compiled into the app. Anyone who has a build made with your key can pull the key out of it, and everyone using a build shares that key's free-tier limits. Use it only for development and our research study. Never publish a web, APK or store build made with `env.json`, and never commit `env.json`. Before any public release, `GroqAssistBackend` must be replaced by a backend that talks to our own proxy (see `llm-proxy/README.md`).

The Assist tab (study condition "Assist") lets the user describe a problem in plain words, for example "I can't hit the buttons". An online model on Groq proposes one accessibility setting change through function calling. Our own code checks the proposal, the user sees a preview and taps Apply, and Undo is offered afterwards. Without a key, without a network, or when Groq fails, the on-device model (FunctionGemma through LiteRT-LM) answers instead, once it is set up in the tab.

Only the text typed in the Assist tab (with Matrix IDs, links, e-mail addresses and the names of the user's rooms and contacts removed), the current size settings, the system prompt and the tool schemas are sent. Messages, rooms and contacts are never sent. Groq does see the phone's IP address.

## 1. Get a free Groq key

1. Sign up at <https://console.groq.com>. The free plan needs no card.
2. Open **API Keys** and choose **Create API Key**. The key starts with `gsk_`.
3. Check **Settings → Limits** for your account. For `openai/gpt-oss-20b` the free limits are about 30 requests and 8,000 tokens per minute, and 1,000 requests and 200,000 tokens per day. One Assist request is about 1,500 tokens, so the per-minute token limit is the one you hit first.

## 2. Fill in env.json

```bash
cp env.example.json env.json
```

Then edit `env.json`:

| Key | Value |
| --- | --- |
| `GROQ_API_KEY` | Your key. The placeholder counts as no key. |
| `GROQ_MODEL` | A Groq model that supports tool use. `openai/gpt-oss-20b` was checked on Nov 11, 2026; see <https://console.groq.com/docs/tool-use> and <https://console.groq.com/docs/deprecations> before changing it. |
| `GROQ_REASONING_EFFORT` | `low` for the gpt-oss models. Leave it empty for models that do not accept `reasoning_effort`. |

`env.json` is in `.gitignore`. Do not paste the key anywhere else.

## 3. Run the app

```bash
flutter run --dart-define-from-file=env.json
```

The same flag works for `flutter build`, for example `./scripts/build_study_apk.sh --dart-define-from-file=env.json`. Without it, the Assist tab uses only the on-device model, and debug builds show a short developer note at the top of the tab saying why.

Each answer in the tab is marked "Online assistant" or "On this phone". When Groq's rate limit is reached, the tab first asks the user to wait a moment, then lets the on-device model answer.

## 4. Evaluate the model

```bash
flutter test tool/assist_eval.dart
```

This sends 33 generated requests in English and Danish through the app's own Groq client and prints the valid tool-call rate, how often the right setting was chosen, invalid and out-of-range proposals, and latency. Results are written to `build/assist_eval/`. It paces itself to the per-minute token limit, so a full run takes about eight minutes and uses about 60,000 of the key's daily tokens. Everyone using the key shares those tokens. Options:

- `--dart-define=EVAL_ONLY=en-buttons-hit,da-too-big` runs only those cases
- `--dart-define=EVAL_LIMIT=5` stops after five cases
- `--dart-define=EVAL_TPM=8000` and `--dart-define=EVAL_RPM=30` set the limits it paces to
- `--dart-define=EVAL_DRY_RUN=true` checks the script with canned answers, without a key or any quota

## Where things are

- `lib/personalization/assist/groq_assist_backend.dart`: the Groq client (dev-only)
- `lib/personalization/assist/hybrid_assist_backend.dart`: online first, on-device fallback, rate-limit handling
- `lib/personalization/settings_registry.dart`: the settings the model may change; its doc comment explains how to add one
- `assets/assist/heuristics.md`: the system prompt and heuristics, which the team edits without code changes
- `lib/personalization/assist/assist_validator.dart`: checks every proposal before the user sees it


# Special thanks

* <a href="https://github.com/fabiyamada">Fabiyamada</a> is a graphics designer and has made the fluffychat logo and the banner. Big thanks for her great designs.

* Also thanks to all translators and testers! With your help, fluffychat is now available in more than 12 languages.

* The Matrix Foundation for making and maintaining the [emoji translations](https://github.com/matrix-org/matrix-spec/blob/main/data-definitions/sas-emoji.json) used for emoji verification, licensed Apache 2.0

* Special thanks to MTRNord, Sorunome and Advocatux.