// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { estimateTokens, sanitize } from '../src/sanitize.js';
import { validBody } from './helpers.js';

describe('sanitize', () => {
  it('keeps messages, tools and tool_choice and drops everything else', () => {
    const result = sanitize({
      ...validBody,
      model: 'some-expensive-model',
      max_tokens: 100000,
      stream: true,
      user: '@alice:example.org',
      messages: [
        ...validBody.messages.slice(0, 1),
        { role: 'user', content: 'hi', name: 'Alice', extra: 1 },
      ],
      tools: [{ ...validBody.tools[0], cache: true }],
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(Object.keys(result.request).sort()).toEqual([
      'messages',
      'tool_choice',
      'tools',
    ]);
    expect(result.request.messages[1]).toEqual({ role: 'user', content: 'hi' });
    expect(Object.keys(result.request.tools[0]!)).toEqual(['type', 'function']);
  });

  const user = (content: unknown) => ({ role: 'user', content });
  it.each<[string, unknown]>([
    ['a body that is not an object', 'x'],
    ['no messages', { messages: [] }],
    ['too many messages', { messages: Array(5).fill(user('a')) }],
    ['a tool role', { messages: [{ role: 'tool', content: 'a' }] }],
    ['non-string content', { messages: [user([{ type: 'image_url' }])] }],
    [
      'a last message not from the user',
      { messages: [user('a'), { role: 'assistant', content: 'b' }] },
    ],
    ['a request that is too long', { messages: [user('a'.repeat(12_001))] }],
    [
      'a bad tool name',
      {
        ...validBody,
        tools: [{ type: 'function', function: { name: 'x y', parameters: {} } }],
      },
    ],
    [
      'a tool choice that was not offered',
      {
        ...validBody,
        tool_choice: { type: 'function', function: { name: 'other' } },
      },
    ],
  ])('rejects %s', (_, body) => {
    expect(sanitize(body).ok).toBe(false);
  });

  it('estimates about four characters per token', () => {
    const result = sanitize(validBody);
    if (!result.ok) throw new Error(result.reason);
    const chars = JSON.stringify({
      m: result.request.messages,
      t: result.request.tools,
    }).length;
    expect(estimateTokens(result.request)).toBe(Math.ceil(chars / 4));
  });
});
