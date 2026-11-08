// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { buildBody, callProvider } from '../src/providers.js';
import { sanitize } from '../src/sanitize.js';
import { completion, json, provider, validBody } from './helpers.js';

const request = (() => {
  const r = sanitize(validBody);
  if (!r.ok) throw new Error(r.reason);
  return r.request;
})();
const options = { maxTokens: 300, temperature: 0.2 };

describe('buildBody', () => {
  it('forces the model and limits and adds provider extras', () => {
    const body = buildBody(
      provider('groq', {
        extraBody: { reasoning_effort: 'low', model: 'ignored' },
      }),
      request,
      options,
    );
    expect(body.model).toBe('groq-model');
    expect(body.max_tokens).toBe(300);
    expect(body.reasoning_effort).toBe('low');
    expect(body).not.toHaveProperty('parallel_tool_calls');
  });

  it('sends parallel_tool_calls only when configured', () => {
    const body = buildBody(
      provider('x', { parallelToolCalls: false }),
      request,
      options,
    );
    expect(body.parallel_tool_calls).toBe(false);
  });
});

describe('callProvider', () => {
  it('sends the key and returns only content and tool calls', async () => {
    let seen: RequestInit | undefined;
    const result = await callProvider(
      provider('groq'),
      request,
      options,
      async (url, init) => {
        expect(String(url)).toBe('https://groq.example/v1/chat/completions');
        seen = init;
        return json(200, completion('set_button_scale'));
      },
    );
    expect((seen?.headers as Record<string, string>).authorization).toBe(
      'Bearer key-groq',
    );
    expect(result.kind).toBe('ok');
    if (result.kind !== 'ok') return;
    expect(result.message).toEqual({
      role: 'assistant',
      content: null,
      tool_calls: [
        {
          id: 'call_1',
          type: 'function',
          function: { name: 'set_button_scale', arguments: '{"value":1.3}' },
        },
      ],
    });
    expect(result.usage?.prompt_tokens).toBe(420);
  });

  it.each<[number, unknown, string]>([
    [429, {}, 'rate_limited'],
    [500, {}, 'server_error'],
    [503, {}, 'server_error'],
    [401, {}, 'key_rejected'],
    [400, { error: { code: 'tool_use_failed' } }, 'tool_use_failed'],
  ])('asks for the next provider on %i', async (status, body, reason) => {
    const result = await callProvider(provider('groq'), request, options, async () =>
      json(status, body),
    );
    expect(result).toEqual({ kind: 'retry', status, reason });
  });

  it('fails on other client errors', async () => {
    const result = await callProvider(provider('groq'), request, options, async () =>
      json(400, { error: { code: 'invalid_request' } }),
    );
    expect(result).toEqual({ kind: 'fail', status: 400, reason: 'invalid_request' });
  });

  it('treats a timeout as retryable', async () => {
    const result = await callProvider(
      provider('slow', { timeoutMs: 20 }),
      request,
      options,
      (_, init) =>
        new Promise((_, reject) => {
          init?.signal?.addEventListener('abort', () =>
            reject(init.signal!.reason),
          );
        }),
    );
    expect(result).toEqual({ kind: 'retry', status: null, reason: 'timeout' });
  });

  it('treats a network error as retryable', async () => {
    const result = await callProvider(provider('down'), request, options, async () => {
      throw new TypeError('fetch failed');
    });
    expect(result).toEqual({ kind: 'retry', status: null, reason: 'network' });
  });
});
