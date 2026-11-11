# LLM proxy for the Assist widget

The proxy sits between the app's Assist widget and free-tier LLM APIs.

> **Not used by the app right now (Nov 11, 2026).** For development and the research study the app calls Groq directly with a key from `env.json` (see the main README, "AI Assist (development only)"). That key is extractable from the app, so before any public release the app must go back to a proxy like this one. The app's proxy backend was removed in commit `a43ff0ce2` (see it with `git show a43ff0ce2^:lib/personalization/assist/remote_assist_backend.dart`). A new one only needs to build its request with `AssistChatFormat` in `lib/personalization/assist/assist_chat_format.dart`.

The proxy holds the provider API keys, so the app and the repository hold none. Only signed-in users of our homeserver can use it. It moves to the next provider when one fails. It also limits how often each user can call it, so one person cannot use up the shared free tier.

```
App (Assist tab) ──HTTPS──▶ reverse proxy ──▶ llm-proxy ──▶ Groq (later: more providers)
                                               │
                                               └──▶ Synapse /_matrix/federation/v1/openid/userinfo
```

## What leaves the phone

The app sends three things:

- the system prompt from `assets/assist/heuristics.md`
- the user's Assist text, plus at most one earlier clarifying exchange
- the current accessibility setting values, and the tool schemas built from the app's settings registry

The app never sends messages, rooms, contact names or Matrix IDs. It also strips IDs and links out of the prompt before sending it.

The proxy forwards only `messages`, `tools` and `tool_choice`. It sets the model, `max_tokens` and `temperature` itself.

## Endpoint

`POST /v1/assist` takes the OpenAI chat-completions format: `messages`, `tools` and `tool_choice`.

| Status | Body | Meaning for the app |
| --- | --- | --- |
| 200 | `{message, usage, assist: {provider, model}}` | `message.tool_calls` or `message.content` |
| 401 | `error.code = ASSIST_UNAUTHORIZED` | The token is missing or invalid, or the user is not on our homeserver |
| 429 | `error.code = ASSIST_RATE_LIMITED`, `Retry-After` | This user sent more than `RATE_LIMIT_PER_MIN` requests in a minute |
| 400 | `error.code = ASSIST_BAD_REQUEST` | The body is not in the accepted shape |
| 503 | `error.code = ASSIST_FALLBACK` | No provider answered, so the app uses the on-device model |
| 503 | `error.code = ASSIST_AUTH_UNAVAILABLE` | The proxy cannot reach Synapse |

`GET /healthz` returns `{"ok": true}` and needs no token.

## Auth: Matrix OpenID tokens

The app does not send its Matrix access token. It sends a short-lived OpenID token instead:

1. The app asks Synapse for a token: `POST /_matrix/client/v3/user/{userId}/openid/request_token`. The token is valid for about an hour.
2. The app sends it as `Authorization: Bearer <token>`.
3. The proxy checks it with `GET {SYNAPSE_URL}/_matrix/federation/v1/openid/userinfo?access_token=<token>`. It accepts the request only if the returned `sub` ends in `:${HOMESERVER_NAME}`.
4. The proxy caches a successful check for `AUTH_CACHE_TTL_S` seconds, keyed by the token's hash. Rejections are not cached.

An OpenID token can only prove who the user is. It cannot read or send messages. That means a leaked proxy log, or a compromised proxy, can never act as the user.

## Home server setup

We did not find the Synapse deployment while building this. The steps below assume Synapse runs in Docker behind a reverse proxy. Adapt the names to match your setup.

### 1. Let the proxy reach Synapse's openid endpoint

The `userinfo` endpoint is served by the `openid` resource. The `federation` resource also includes it. The proxy reaches Synapse over the internal Docker network, so the endpoint does not have to be public.

In `homeserver.yaml`, make sure the listener the proxy talks to has one of those resources. For example:

```yaml
listeners:
  - port: 8008
    type: http
    tls: false
    x_forwarded: true
    bind_addresses: ['0.0.0.0']
    resources:
      - names: [client, openid]   # or [client, federation]
        compress: false
```

Restart Synapse after the change. To check it from inside the network, run this. It should print `401` and `M_UNKNOWN_TOKEN`, not `404`:

```bash
docker run --rm --network synapse curlimages/curl -s -w '\n%{http_code}\n' "http://synapse:8008/_matrix/federation/v1/openid/userinfo?access_token=test"
```

### 2. Put the proxy on Synapse's Docker network

Find the network name:

```bash
docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' synapse
```

Then set `SYNAPSE_NETWORK` in `.env` to that name, and set `SYNAPSE_URL` to `http://<synapse container name>:8008`.

### 3. Route `/_assist/` through the reverse proxy

Serve the proxy on the same domain as Synapse, under `/_assist/`. Strip that prefix, so that `https://matrix.example.org/_assist/v1/assist` reaches `llm-proxy:8080/v1/assist`. Don't put it under `/_matrix/`, because that path belongs to Synapse. Use the snippet for the reverse proxy you run.

**Caddy**

```caddy
matrix.example.org {
	handle_path /_assist/* {
		reverse_proxy llm-proxy:8080
	}
	reverse_proxy /_matrix/* synapse:8008
	reverse_proxy /_synapse/client/* synapse:8008
}
```

**nginx** (inside the existing `server { ... }` block for the Matrix domain)

```nginx
location /_assist/ {
    proxy_pass http://llm-proxy:8080/;   # trailing slash strips /_assist/
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $host;
    client_max_body_size 64k;
    proxy_read_timeout 30s;
}
```

**Traefik** (labels to add under `llm-proxy` in `docker-compose.yml`)

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.llm-proxy.rule=Host(`matrix.example.org`) && PathPrefix(`/_assist/`)
      - traefik.http.routers.llm-proxy.entrypoints=websecure
      - traefik.http.routers.llm-proxy.tls=true
      - traefik.http.middlewares.llm-proxy-strip.stripprefix.prefixes=/_assist
      - traefik.http.routers.llm-proxy.middlewares=llm-proxy-strip
      - traefik.http.services.llm-proxy.loadbalancer.server.port=8080
```

### 4. Start it

```bash
cd llm-proxy
cp .env.example .env
```

Edit `.env` and fill in `GROQ_API_KEY`, `HOMESERVER_NAME`, `LOG_SALT` and `SYNAPSE_URL`. Then build and start the container:

```bash
docker compose up -d --build
```

Follow the logs:

```bash
docker compose logs -f llm-proxy
```

### 5. Point the app at it

The app cannot use the proxy at the moment (see the note at the top). The removed proxy backend read the URL like this; the URL is not a secret.

```bash
flutter build apk --dart-define=ASSIST_PROXY_URL=https://matrix.example.org/_assist/v1/assist
```

The web build reads `assistProxyUrl` from `config.json` instead. If no URL is set, the Assist tab uses only the on-device model.

## Getting a free Groq key

1. Sign up at <https://console.groq.com>. The free plan needs no card.
2. Open **API Keys** and choose **Create API Key**. Copy the key into `GROQ_API_KEY` in the server's `.env` and nowhere else.
3. Check **Settings → Limits** for your account's real limits.

The docs listed these limits for `openai/gpt-oss-20b` when this was written (Nov 2026):

| Requests per minute | Requests per day | Tokens per minute | Tokens per day |
| --- | --- | --- | --- |
| 30 | 1,000 | 8,000 | 200,000 |

A request from the app is about 1,500 tokens. That gives roughly 5 requests per minute and 130 per day across all users, so the per-user rate limit matters.

Models are set in `config/providers.json`, not in code. On Nov 8, 2026, Groq listed these production models with tool calling:

- `openai/gpt-oss-20b` (the default). Fast, and supports tools. It does not support parallel tool calls, so the config leaves `parallelToolCalls` unset. It gets `reasoning_effort: "low"` to keep latency down.
- `openai/gpt-oss-120b`. Bigger, with the same free-tier limits.
- `llama-3.3-70b-versatile`. Supports parallel tool calls; if you use it, set `"parallelToolCalls": false` so it proposes one change at a time.

Check <https://console.groq.com/docs/tool-use> and <https://console.groq.com/docs/deprecations> before changing models. Then compare them with the app's evaluation script, `flutter test tool/assist_eval.dart` (see the main README).

### Adding another provider

Any OpenAI-compatible API works. Add an entry to `config/providers.json`, put it in the order you want it tried, and add its key variable to `.env`. A provider whose key variable is empty is skipped.

Mistral is left out for now. Its free "Experiment" tier requires opting in to training on your requests. Assist prompts can describe health or disabilities, so the study's ethics approval and consent have to cover that first.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `GROQ_API_KEY` | (required) | Groq key. Each provider names its own variable in `providers.json`. |
| `SYNAPSE_URL` | (required) | Synapse as the proxy reaches it, e.g. `http://synapse:8008` |
| `HOMESERVER_NAME` | (required) | Only `@user:HOMESERVER_NAME` is accepted |
| `LOG_SALT` | (required) | HMAC salt for hashing user IDs in logs, at least 16 characters |
| `STUDY_LOGGING` | `false` | Also logs the user's Assist prompt. See the privacy note below. |
| `PORT` | `8080` | Listen port |
| `RATE_LIMIT_PER_MIN` | `10` | Requests per user per minute |
| `AUTH_CACHE_TTL_S` | `60` | How long a successful token check is cached |
| `TOKEN_BUDGET_WARN` | `2500` | Logs a warning when a request's prompt tokens are above this |
| `MAX_TOKENS` | `300` | `max_tokens` sent to the provider |
| `ALLOW_PROVIDER_OVERRIDE` | `false` | Lets the `X-Assist-Provider` header pick a provider (evaluation only) |
| `PROVIDERS_FILE` | `config/providers.json` | Another providers file |
| `SYNAPSE_NETWORK` | `synapse` | Docker network that `docker-compose.yml` joins |

## Logs

Logs are JSON lines on stdout, so `docker compose logs` shows them. Each request writes one line:

```json
{"ts":"2026-11-08T12:00:00.000Z","level":"info","event":"assist","user":"3f9a…","provider":"groq","model":"openai/gpt-oss-20b","latency_ms":612,"prompt_tokens":1430,"completion_tokens":41,"tools_called":["set_button_scale"],"failed_over":[]}
```

Other events are `assist_fallback` (every provider failed, with the attempts), `token_budget_exceeded`, `rate_limited`, `auth_rejected` and `bad_request`.

The `user` field is an HMAC of the Matrix ID, not the ID itself. Tokens, keys and prompt text are never logged.

**Privacy note on `STUDY_LOGGING`.** When it is on, every `assist` line also contains the user's prompt text. Prompts can describe health or disabilities. Turn it on only for study sessions whose consent covers it, and delete the logs after the study. It is also worth knowing that with or without this flag, the prompt and the current settings are sent to Groq.

## Development

You need Node 22 or newer.

Install the dependencies:

```bash
npm ci
```

Run the tests. Providers and Synapse are mocked, so this needs no network:

```bash
npm test
```

Typecheck the source and the tests:

```bash
npm run typecheck
```

Compile to `dist/`:

```bash
npm run build
```

To run the proxy locally without Docker, set the variables from `.env.example` and run `npm run dev`.

## Evaluation script

The evaluation moved to the app: `tool/assist_eval.dart` sends generated requests to Groq through the app's own `GroqAssistBackend`. See the main README, "AI Assist (development only)".
