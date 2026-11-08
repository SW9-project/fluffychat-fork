// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Accepts only the parts of an OpenAI chat-completions request the Assist
 * widget needs, and drops everything else. The app sends a system prompt,
 * the user's Assist text (and at most one earlier clarifying exchange) and
 * the tool schemas; nothing else is forwarded to a provider.
 */

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface ToolDefinition {
  type: 'function';
  function: {
    name: string;
    description?: string;
    parameters: Record<string, unknown>;
  };
}

export type ToolChoice =
  | 'auto'
  | 'none'
  | 'required'
  | { type: 'function'; function: { name: string } };

export interface AssistRequest {
  messages: ChatMessage[];
  tools: ToolDefinition[];
  tool_choice?: ToolChoice;
}

export const limits = {
  maxMessages: 4,
  maxChars: 12_000,
  maxTools: 16,
  maxDescription: 1024,
} as const;

export type SanitizeResult =
  | { ok: true; request: AssistRequest }
  | { ok: false; reason: string };

const roles = new Set(['system', 'user', 'assistant']);
const toolName = /^[A-Za-z0-9_-]{1,64}$/;

function fail(reason: string): SanitizeResult {
  return { ok: false, reason };
}

export function sanitize(body: unknown): SanitizeResult {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return fail('body must be a JSON object');
  }
  const b = body as Record<string, unknown>;

  if (!Array.isArray(b.messages) || b.messages.length === 0) {
    return fail('messages must be a non-empty array');
  }
  if (b.messages.length > limits.maxMessages) {
    return fail(`at most ${limits.maxMessages} messages`);
  }
  const messages: ChatMessage[] = [];
  let chars = 0;
  for (const m of b.messages as unknown[]) {
    const o = (m ?? {}) as Record<string, unknown>;
    if (typeof o.role !== 'string' || !roles.has(o.role)) {
      return fail('message role must be system, user or assistant');
    }
    if (typeof o.content !== 'string') {
      return fail('message content must be a string');
    }
    chars += o.content.length;
    messages.push({ role: o.role as ChatMessage['role'], content: o.content });
  }
  if (messages.at(-1)?.role !== 'user') {
    return fail('the last message must be from the user');
  }

  const tools: ToolDefinition[] = [];
  if (b.tools !== undefined) {
    if (!Array.isArray(b.tools)) return fail('tools must be an array');
    if (b.tools.length > limits.maxTools) {
      return fail(`at most ${limits.maxTools} tools`);
    }
    for (const t of b.tools as unknown[]) {
      const o = (t ?? {}) as Record<string, unknown>;
      const f = (o.function ?? {}) as Record<string, unknown>;
      if (o.type !== 'function') return fail('tool type must be function');
      if (typeof f.name !== 'string' || !toolName.test(f.name)) {
        return fail('tool name must match [A-Za-z0-9_-]{1,64}');
      }
      if (f.description !== undefined && typeof f.description !== 'string') {
        return fail('tool description must be a string');
      }
      if (
        typeof f.description === 'string' &&
        f.description.length > limits.maxDescription
      ) {
        return fail(`tool description longer than ${limits.maxDescription}`);
      }
      if (
        typeof f.parameters !== 'object' ||
        f.parameters === null ||
        Array.isArray(f.parameters)
      ) {
        return fail('tool parameters must be a JSON schema object');
      }
      const def: ToolDefinition = {
        type: 'function',
        function: {
          name: f.name,
          parameters: f.parameters as Record<string, unknown>,
        },
      };
      if (typeof f.description === 'string') {
        def.function.description = f.description;
      }
      tools.push(def);
      chars += JSON.stringify(def).length;
    }
  }
  if (chars > limits.maxChars) {
    return fail(`request larger than ${limits.maxChars} characters`);
  }

  const request: AssistRequest = { messages, tools };
  const choice = b.tool_choice;
  if (choice !== undefined) {
    if (choice === 'auto' || choice === 'none' || choice === 'required') {
      request.tool_choice = choice;
    } else {
      const o = (choice ?? {}) as Record<string, unknown>;
      const name = (o.function as Record<string, unknown> | undefined)?.name;
      if (
        o.type !== 'function' ||
        typeof name !== 'string' ||
        !tools.some((t) => t.function.name === name)
      ) {
        return fail('tool_choice must be auto, none, required or an offered tool');
      }
      request.tool_choice = { type: 'function', function: { name } };
    }
  }
  return { ok: true, request };
}

/** Rough token estimate (about four characters per token). */
export function estimateTokens(request: AssistRequest): number {
  return Math.ceil(
    JSON.stringify({ m: request.messages, t: request.tools }).length / 4,
  );
}
