// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { ResolvedProvider } from './config.js';
import type { AssistRequest } from './sanitize.js';

/** One OpenAI-compatible client for every provider: base URL, model and key. */

export interface ToolCall {
  id: string;
  type: 'function';
  function: { name: string; arguments: string };
}

export interface AssistantMessage {
  role: 'assistant';
  content: string | null;
  tool_calls?: ToolCall[];
}

export interface Usage {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

export type ProviderResult =
  | { kind: 'ok'; message: AssistantMessage; usage: Usage | null }
  /** Try the next provider: 429, 5xx, timeout, network error, bad key, malformed tool call. */
  | { kind: 'retry'; status: number | null; reason: string }
  /** The request itself was refused; another provider would refuse it too. */
  | { kind: 'fail'; status: number; reason: string };

export type Fetch = typeof fetch;

export interface CallOptions {
  maxTokens: number;
  temperature: number;
}

export function buildBody(
  provider: ResolvedProvider,
  request: AssistRequest,
  options: CallOptions,
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    ...provider.extraBody,
    model: provider.model,
    messages: request.messages,
    max_tokens: options.maxTokens,
    temperature: options.temperature,
  };
  if (request.tools.length > 0) {
    body.tools = request.tools;
    if (request.tool_choice !== undefined) body.tool_choice = request.tool_choice;
    if (provider.parallelToolCalls !== undefined) {
      body.parallel_tool_calls = provider.parallelToolCalls;
    }
  }
  return body;
}

function errorCode(json: unknown): string | undefined {
  const error = (json as { error?: { code?: unknown } } | null)?.error;
  return typeof error?.code === 'string' ? error.code : undefined;
}

function parseMessage(json: unknown): AssistantMessage | null {
  const message = (json as { choices?: { message?: unknown }[] } | null)
    ?.choices?.[0]?.message as Record<string, unknown> | undefined;
  if (!message) return null;
  const out: AssistantMessage = {
    role: 'assistant',
    content: typeof message.content === 'string' ? message.content : null,
  };
  if (Array.isArray(message.tool_calls)) {
    const calls: ToolCall[] = [];
    for (const raw of message.tool_calls as unknown[]) {
      const c = (raw ?? {}) as Record<string, unknown>;
      const f = (c.function ?? {}) as Record<string, unknown>;
      if (typeof f.name !== 'string') continue;
      calls.push({
        id: typeof c.id === 'string' ? c.id : '',
        type: 'function',
        function: {
          name: f.name,
          arguments:
            typeof f.arguments === 'string'
              ? f.arguments
              : JSON.stringify(f.arguments ?? {}),
        },
      });
    }
    if (calls.length > 0) out.tool_calls = calls;
  }
  return out;
}

function parseUsage(json: unknown): Usage | null {
  const u = (json as { usage?: Record<string, unknown> } | null)?.usage;
  if (!u) return null;
  const n = (v: unknown) => (typeof v === 'number' ? v : 0);
  return {
    prompt_tokens: n(u.prompt_tokens),
    completion_tokens: n(u.completion_tokens),
    total_tokens: n(u.total_tokens),
  };
}

export async function callProvider(
  provider: ResolvedProvider,
  request: AssistRequest,
  options: CallOptions,
  fetchFn: Fetch = fetch,
): Promise<ProviderResult> {
  let response: Response;
  try {
    response = await fetchFn(`${provider.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${provider.apiKey}`,
      },
      body: JSON.stringify(buildBody(provider, request, options)),
      signal: AbortSignal.timeout(provider.timeoutMs),
    });
  } catch (e) {
    const name = (e as Error)?.name;
    const timedOut = name === 'TimeoutError' || name === 'AbortError';
    return { kind: 'retry', status: null, reason: timedOut ? 'timeout' : 'network' };
  }

  let json: unknown = null;
  try {
    json = await response.json();
  } catch {
    // A body that is not JSON is handled by the status checks below.
  }

  if (response.ok) {
    const message = parseMessage(json);
    if (!message) return { kind: 'retry', status: response.status, reason: 'bad_response' };
    return { kind: 'ok', message, usage: parseUsage(json) };
  }
  const status = response.status;
  if (status === 429) return { kind: 'retry', status, reason: 'rate_limited' };
  if (status >= 500) return { kind: 'retry', status, reason: 'server_error' };
  if (status === 401 || status === 403) {
    return { kind: 'retry', status, reason: 'key_rejected' };
  }
  if (status === 400 && errorCode(json) === 'tool_use_failed') {
    return { kind: 'retry', status, reason: 'tool_use_failed' };
  }
  return { kind: 'fail', status, reason: errorCode(json) ?? 'rejected' };
}
