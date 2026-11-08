// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { ProxyConfig, ResolvedProvider } from '../src/config.js';

export function provider(
  name: string,
  overrides: Partial<ResolvedProvider> = {},
): ResolvedProvider {
  return {
    name,
    baseUrl: `https://${name}.example/v1`,
    model: `${name}-model`,
    apiKeyEnv: `${name.toUpperCase()}_API_KEY`,
    apiKey: `key-${name}`,
    timeoutMs: 200,
    enabled: true,
    ...overrides,
  };
}

export function config(overrides: Partial<ProxyConfig> = {}): ProxyConfig {
  return {
    port: 0,
    synapseUrl: 'http://synapse.internal:8008',
    homeserverName: 'example.org',
    logSalt: 'a-test-salt-of-16+chars',
    rateLimitPerMin: 10,
    authCacheTtlS: 60,
    studyLogging: false,
    tokenBudgetWarn: 2500,
    allowProviderOverride: false,
    maxTokens: 300,
    temperature: 0.2,
    providers: [provider('groq'), provider('backup')],
    ...overrides,
  };
}

export const validBody = {
  messages: [
    { role: 'system', content: 'You are an accessibility assistant.' },
    { role: 'user', content: 'I cannot hit the buttons' },
  ],
  tools: [
    {
      type: 'function',
      function: {
        name: 'set_button_scale',
        description: 'Size of icons on buttons.',
        parameters: {
          type: 'object',
          properties: { value: { type: 'number', minimum: 1, maximum: 2 } },
          required: ['value'],
        },
      },
    },
  ],
  tool_choice: 'auto',
};

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export function completion(toolName?: string, args: unknown = { value: 1.3 }) {
  return {
    choices: [
      {
        message: toolName
          ? {
              role: 'assistant',
              content: null,
              reasoning: 'internal reasoning that must not be forwarded',
              tool_calls: [
                {
                  id: 'call_1',
                  type: 'function',
                  function: { name: toolName, arguments: JSON.stringify(args) },
                },
              ],
            }
          : { role: 'assistant', content: 'Which buttons do you mean?' },
      },
    ],
    usage: { prompt_tokens: 420, completion_tokens: 30, total_tokens: 450 },
  };
}
