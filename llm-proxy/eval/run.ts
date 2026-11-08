// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Sends the generated cases through the proxy, like the app does, and
 * reports how well the online model picks settings.
 *
 *   EVAL_OPENID_TOKEN=... npm run eval -- [--url URL] [--provider groq]
 *       [--delay-ms 7000] [--limit N] [--only id1,id2]
 *
 * Requests are sent one at a time with a pause between them, so the run
 * stays under the proxy's per-user limit (10 per minute) and the free tier.
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { cases } from './cases.js';
import {
  type Answer,
  defaults,
  loadFixture,
  requestBody,
  type Scored,
  score,
  summarize,
  systemPrompt,
} from './lib.js';

function option(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const url = option('url') ?? process.env.EVAL_PROXY_URL ?? 'http://localhost:8080/v1/assist';
const token = process.env.EVAL_OPENID_TOKEN;
const provider = option('provider');
const delayMs = Number(option('delay-ms') ?? 7000);
const limit = Number(option('limit') ?? cases.length);
const only = option('only')?.split(',');

if (!token) {
  console.error('Set EVAL_OPENID_TOKEN to an OpenID token of a test user (see eval/README.md).');
  process.exit(1);
}

const fixture = loadFixture();
const defaultSystem = systemPrompt(fixture, defaults(fixture));
if (defaultSystem !== fixture.systemWithDefaults) {
  console.error('The eval would build a different system prompt than the app. Regenerate the fixture.');
  process.exit(1);
}

const selected = cases.filter((c) => !only || only.includes(c.id)).slice(0, limit);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function send(prompt: string, settings: Record<string, number>): Promise<Answer> {
  const started = performance.now();
  let status = 0;
  let json: Record<string, any> | null = null;
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${token}`,
        ...(provider ? { 'x-assist-provider': provider } : {}),
      },
      body: JSON.stringify(requestBody(fixture, settings, prompt)),
      signal: AbortSignal.timeout(30_000),
    });
    status = response.status;
    json = (await response.json().catch(() => null)) as Record<string, any> | null;
  } catch (e) {
    return {
      status: 0, provider: null, latencyMs: Math.round(performance.now() - started),
      promptTokens: null, calls: [], text: null, errorCode: (e as Error).name,
    };
  }
  const message = json?.message ?? {};
  return {
    status,
    provider: json?.assist?.provider ?? null,
    latencyMs: Math.round(performance.now() - started),
    promptTokens: json?.usage?.prompt_tokens ?? null,
    calls: (message.tool_calls ?? []).map((c: any) => ({
      name: String(c?.function?.name ?? ''),
      arguments: String(c?.function?.arguments ?? ''),
    })),
    text: typeof message.content === 'string' ? message.content : null,
    errorCode: json?.error?.code ?? (status === 200 ? null : `http_${status}`),
  };
}

const results: Scored[] = [];
for (const [i, c] of selected.entries()) {
  if (i > 0) await sleep(delayMs);
  let answer = await send(c.prompt, { ...defaults(fixture), ...c.settings });
  if (answer.status === 429) {
    // Our own per-user limit or the provider's: wait a minute once.
    await sleep(61_000);
    answer = await send(c.prompt, { ...defaults(fixture), ...c.settings });
  }
  const r = score(fixture, c, answer);
  results.push(r);
  const what = r.calledTool
    ? `${r.setting ?? 'INVALID'}${r.to !== null ? ` -> ${r.to}` : ''}`
    : r.text ? `text: ${r.text.slice(0, 60)}` : r.errorCode ?? 'nothing';
  console.log(
    `${r.correct ? 'ok  ' : 'MISS'} ${c.id.padEnd(22)} ${String(r.latencyMs).padStart(5)} ms  ${r.provider ?? '-'}  ${what}`,
  );
}

const summary = summarize(results);
console.log('\n' + JSON.stringify(summary, null, 2));

const dir = fileURLToPath(new URL('./results/', import.meta.url));
mkdirSync(dir, { recursive: true });
const file = `${dir}${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
writeFileSync(file, JSON.stringify({ url, provider: provider ?? null, summary, results }, null, 2));
console.log(`\nSaved ${file}`);
