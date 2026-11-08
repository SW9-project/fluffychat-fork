// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import type { ProxyConfig } from '../src/config.js';
import { jsonLogger } from '../src/log.js';
import type { Fetch } from '../src/providers.js';
import { completion, config, json, provider, validBody } from './helpers.js';

type Handler = (init?: RequestInit) => Promise<Response> | Response;

/** Fake network: Synapse plus one handler per provider host. */
function network(providers: Record<string, Handler>) {
  const providerCalls: string[] = [];
  const fetchFn: Fetch = async (input, init) => {
    const url = new URL(String(input));
    if (url.host === 'synapse.internal:8008') {
      const token = url.searchParams.get('access_token');
      if (token === 'alicetoken') return json(200, { sub: '@alice:example.org' });
      if (token === 'bobtoken') return json(200, { sub: '@bob:example.org' });
      if (token === 'foreigntoken') return json(200, { sub: '@eve:matrix.org' });
      return json(401, { errcode: 'M_UNKNOWN_TOKEN' });
    }
    const name = url.host.replace('.example', '');
    providerCalls.push(name);
    const handler = providers[name];
    if (!handler) throw new TypeError('fetch failed');
    return handler(init);
  };
  return { fetchFn, providerCalls };
}

let app: FastifyInstance | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

function start(
  providers: Record<string, Handler>,
  overrides: Partial<ProxyConfig> = {},
) {
  const lines: Record<string, unknown>[] = [];
  const net = network(providers);
  app = buildApp({
    config: config(overrides),
    fetch: net.fetchFn,
    logger: jsonLogger((line) => lines.push(JSON.parse(line))),
  });
  const post = (
    body: unknown = validBody,
    token: string | null = 'alicetoken',
    headers: Record<string, string> = {},
  ) =>
    app!.inject({
      method: 'POST',
      url: '/v1/assist',
      headers: token ? { authorization: `Bearer ${token}`, ...headers } : headers,
      payload: body as object,
    });
  return { post, lines, ...net };
}

const ok: Handler = () => json(200, completion('set_button_scale'));

describe('POST /v1/assist', () => {
  it('returns the first provider answer without internal fields', async () => {
    const { post, providerCalls } = start({ groq: ok, backup: ok });
    const res = await post();
    expect(res.statusCode).toBe(200);
    expect(res.headers['x-assist-provider']).toBe('groq');
    const body = res.json();
    expect(body.assist).toEqual({ provider: 'groq', model: 'groq-model' });
    expect(body.message.tool_calls[0].function.name).toBe('set_button_scale');
    expect(body.message).not.toHaveProperty('reasoning');
    expect(providerCalls).toEqual(['groq']);
  });

  it('forwards only the sanitised request and forces the model', async () => {
    let sent: Record<string, unknown> = {};
    const { post } = start({
      groq: (init) => {
        sent = JSON.parse(String(init?.body));
        return json(200, completion());
      },
    });
    await post({ ...validBody, model: 'other', stream: true, user: '@alice:example.org' });
    expect(sent.model).toBe('groq-model');
    expect(sent).not.toHaveProperty('stream');
    expect(sent).not.toHaveProperty('user');
    expect(JSON.stringify(sent)).not.toContain('alicetoken');
  });

  describe('failover', () => {
    it.each<[string, Handler]>([
      ['429', () => json(429, { error: { message: 'rate limit' } })],
      ['500', () => json(500, {})],
      ['503', () => json(503, {})],
      ['a malformed tool call', () => json(400, { error: { code: 'tool_use_failed' } })],
      ['a network error', () => Promise.reject(new TypeError('fetch failed'))],
    ])('moves to the next provider after %s', async (_, failing) => {
      const { post, providerCalls, lines } = start({ groq: failing, backup: ok });
      const res = await post();
      expect(res.statusCode).toBe(200);
      expect(res.json().assist.provider).toBe('backup');
      expect(providerCalls).toEqual(['groq', 'backup']);
      const record = lines.find((l) => l.event === 'assist')!;
      expect(record.provider).toBe('backup');
      expect((record.failed_over as unknown[]).length).toBe(1);
    });

    it('moves to the next provider after a timeout', async () => {
      const hang: Handler = (init) =>
        new Promise((_, reject) =>
          init?.signal?.addEventListener('abort', () => reject(init.signal!.reason)),
        );
      const { post } = start(
        { groq: hang, backup: ok },
        { providers: [provider('groq', { timeoutMs: 30 }), provider('backup')] },
      );
      const res = await post();
      expect(res.statusCode).toBe(200);
      expect(res.json().assist.provider).toBe('backup');
    });

    it('returns ASSIST_FALLBACK when every provider fails', async () => {
      const { post, providerCalls, lines } = start({
        groq: () => json(429, {}),
        backup: () => json(502, {}),
      });
      const res = await post();
      expect(res.statusCode).toBe(503);
      expect(res.json().error.code).toBe('ASSIST_FALLBACK');
      expect(providerCalls).toEqual(['groq', 'backup']);
      const record = lines.find((l) => l.event === 'assist_fallback')!;
      expect(record.attempts).toMatchObject([
        { provider: 'groq', outcome: 'rate_limited', status: 429 },
        { provider: 'backup', outcome: 'server_error', status: 502 },
      ]);
    });

    it('does not try further providers when the request itself is refused', async () => {
      const { post, providerCalls } = start({
        groq: () => json(400, { error: { code: 'invalid_request_error' } }),
        backup: ok,
      });
      const res = await post();
      expect(res.statusCode).toBe(503);
      expect(res.json().error.code).toBe('ASSIST_FALLBACK');
      expect(providerCalls).toEqual(['groq']);
    });
  });

  describe('auth', () => {
    it.each<[string, string | null]>([
      ['no token', null],
      ['an unknown token', 'wrongtoken'],
      ['a user from another homeserver', 'foreigntoken'],
    ])('rejects %s with 401 before calling a provider', async (_, token) => {
      const { post, providerCalls } = start({ groq: ok });
      const res = await post(validBody, token);
      expect(res.statusCode).toBe(401);
      expect(res.json().error.code).toBe('ASSIST_UNAUTHORIZED');
      expect(providerCalls).toEqual([]);
    });

    it('rejects a request with an access token in another scheme', async () => {
      const { post } = start({ groq: ok });
      const res = await post(validBody, null, { authorization: 'Basic YWxpY2U6cHc=' });
      expect(res.statusCode).toBe(401);
    });
  });

  describe('rate limit', () => {
    it('refuses the 11th request in a minute for one user only', async () => {
      const { post, providerCalls } = start({ groq: ok });
      for (let i = 0; i < 10; i++) {
        expect((await post()).statusCode).toBe(200);
      }
      const refused = await post();
      expect(refused.statusCode).toBe(429);
      expect(refused.json().error.code).toBe('ASSIST_RATE_LIMITED');
      expect(Number(refused.headers['retry-after'])).toBeGreaterThan(0);
      expect(providerCalls).toHaveLength(10);
      expect((await post(validBody, 'bobtoken')).statusCode).toBe(200);
    });
  });

  it('rejects a malformed body with ASSIST_BAD_REQUEST', async () => {
    const { post } = start({ groq: ok });
    const res = await post({ messages: [{ role: 'tool', content: 'x' }] });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('ASSIST_BAD_REQUEST');
  });

  it('lets the eval pick a provider only when allowed', async () => {
    const off = start({ groq: ok, backup: ok });
    await off.post(validBody, 'alicetoken', { 'x-assist-provider': 'backup' });
    expect(off.providerCalls).toEqual(['groq']);
    await app!.close();

    const on = start({ groq: ok, backup: ok }, { allowProviderOverride: true });
    const res = await on.post(validBody, 'alicetoken', { 'x-assist-provider': 'backup' });
    expect(res.json().assist.provider).toBe('backup');
    expect(on.providerCalls).toEqual(['backup']);
  });

  describe('logging', () => {
    it('logs usage and tools but no prompt, user ID or token by default', async () => {
      const { post, lines } = start({ groq: ok });
      await post();
      const record = lines.find((l) => l.event === 'assist')!;
      expect(record).toMatchObject({
        provider: 'groq',
        model: 'groq-model',
        prompt_tokens: 420,
        completion_tokens: 30,
        tools_called: ['set_button_scale'],
      });
      expect(typeof record.latency_ms).toBe('number');
      expect(record.user).toMatch(/^[0-9a-f]{16}$/);
      expect(typeof record.ts).toBe('string');
      const all = JSON.stringify(lines);
      expect(all).not.toContain('hit the buttons');
      expect(all).not.toContain('alice');
      expect(all).not.toContain('alicetoken');
      expect(all).not.toContain('key-groq');
    });

    it('logs the prompt when STUDY_LOGGING is on', async () => {
      const { post, lines } = start({ groq: ok }, { studyLogging: true });
      await post();
      expect(lines.find((l) => l.event === 'assist')!.prompt).toBe(
        'I cannot hit the buttons',
      );
    });

    it('warns when the request is over the token budget', async () => {
      const { post, lines } = start({ groq: ok }, { tokenBudgetWarn: 400 });
      await post();
      expect(lines.find((l) => l.event === 'token_budget_exceeded')).toMatchObject({
        prompt_tokens: 420,
        budget: 400,
      });
    });

    it('hashes the same user to the same value', async () => {
      const { post, lines } = start({ groq: ok });
      await post();
      await post();
      const users = lines.filter((l) => l.event === 'assist').map((l) => l.user);
      expect(users[0]).toBe(users[1]);
    });
  });

  it('answers the health check without auth', async () => {
    start({});
    const res = await app!.inject({ method: 'GET', url: '/healthz' });
    expect(res.json()).toEqual({ ok: true });
  });
});
