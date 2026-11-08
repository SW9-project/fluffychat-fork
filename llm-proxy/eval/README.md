# Evaluating the online Assist model

`run.ts` sends 31 generated requests through the proxy, the same way the app sends them, and scores the answers. The requests are in English and Danish and cover:

- **specific complaints:** "I can't hit the buttons", "Bogstaverne er for små"
- **the "too big" direction:** these cases start from a text size that is already bigger than normal
- **vague requests:** "It's too small", "Jeg ser dårligt". A short question back counts as correct, and so does a fitting change.
- **an out-of-range request:** "Make the text ten times bigger"
- **off-topic requests:** weather, writing a message, a joke
- **impossible requests:** reading aloud, dark mode, screen brightness

The cases are in `cases.ts`. To add one, add a line there, with `expect` listing every setting that would be a reasonable answer.

## The fixture keeps the evaluation honest

The script does not write its own prompt. It reads `fixtures/assist_request.json`, which holds the app's real system prompt (from `assets/assist/heuristics.md`) and the tool schemas built from the settings registry.

A Flutter test fails when the fixture no longer matches the app. After changing the heuristics or the registry, refresh it from the repo root:

```bash
UPDATE_ASSIST_FIXTURE=1 flutter test test/personalization/assist_eval_fixture_test.dart
```

The scoring uses the same rules as the app's `AssistValidator`:

- the tool must exist
- the heuristic must be one of those offered for that tool
- the value must be a number

The one difference is that the script reports out-of-range values instead of quietly clamping them.

## Running it

1. Start the proxy with a provider key (see `../README.md`).
2. Get an OpenID token for a test user on our homeserver. This takes the test user's access token, so run it yourself and keep the token out of the repo:

   ```bash
   curl -s -X POST -H "Authorization: Bearer $TEST_USER_ACCESS_TOKEN" -H 'content-type: application/json' -d '{}' "https://matrix.example.org/_matrix/client/v3/user/@eval:example.org/openid/request_token"
   ```

   The `access_token` in the answer is valid for about an hour.
3. Run the script:

   ```bash
   EVAL_OPENID_TOKEN=<that token> npm run eval -- --url https://matrix.example.org/_assist/v1/assist
   ```

Options:

| Option | Default | Purpose |
| --- | --- | --- |
| `--url` | `$EVAL_PROXY_URL` or `http://localhost:8080/v1/assist` | The proxy endpoint |
| `--delay-ms` | `7000` | Pause between requests, which stays under the proxy's 10 per minute per user and Groq's free tier |
| `--provider` | (all, in order) | Use only this provider. The proxy must run with `ALLOW_PROVIDER_OVERRIDE=true`. |
| `--limit` | all | Stop after N cases |
| `--only` | all | Comma-separated case ids |

When a request gets HTTP 429, the script waits a minute and tries once more. A full run takes about four minutes and uses roughly 31 × 1,500 = 47,000 tokens of the daily free quota.

To compare providers or models, run the script once per provider with `--provider`. To try another model, change `model` in `config/providers.json` and restart the proxy.

## What it reports

The script prints one line per case, then a summary. It also writes the summary and the per-case results to `results/<timestamp>.json`, which git ignores.

| Field | Meaning |
| --- | --- |
| `validToolCallRate` | Of the answers that called a tool, how many had only valid calls |
| `toolCallRateWhenExpected` | How often a specific complaint got a tool call at all |
| `correctSettingRate` | How often a specific complaint got an acceptable setting, changed in the right direction |
| `vagueHandledRate` / `vagueClarifiedRate` | How often vague requests got a question or a fitting change, and how often a question |
| `noToolWhenNotApplicableRate` | How often off-topic and impossible requests correctly got no tool call |
| `invalidProposals` | Cases with unknown tools, wrong heuristics or unusable values |
| `outOfRangeProposals` | Cases whose value was outside the allowed range. The app clamps these and tells the user. |
| `byLanguage` | The correct rate for English and for Danish |
| `latencyMsByProvider` | Median, p90 and maximum time per provider, measured by the script, so it includes the proxy and the network |
| `promptTokens` | The provider's count of request tokens. The budget is 2,500. |

The script's privacy is the same as the app's. It sends only the generated requests, the system prompt and the setting values. Unless `STUDY_LOGGING` is on, the proxy logs these requests without their text.
