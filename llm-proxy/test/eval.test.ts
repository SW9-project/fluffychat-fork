// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { cases } from '../eval/cases.js';
import {
  type Answer,
  checkCall,
  defaults,
  loadFixture,
  percentile,
  requestBody,
  score,
  summarize,
  systemPrompt,
} from '../eval/lib.js';
import { estimateTokens, sanitize } from '../src/sanitize.js';

const fixture = loadFixture();
const settings = defaults(fixture);

const answer = (overrides: Partial<Answer>): Answer => ({
  status: 200,
  provider: 'groq',
  latencyMs: 500,
  promptTokens: 1400,
  calls: [],
  text: null,
  errorCode: null,
  ...overrides,
});

const call = (name: string, args: Record<string, unknown>) => ({
  name,
  arguments: JSON.stringify(args),
});

describe('fixture', () => {
  it('rebuilds the same system prompt as the app', () => {
    expect(systemPrompt(fixture, settings)).toBe(fixture.systemWithDefaults);
  });

  it('puts changed settings into the prompt', () => {
    expect(systemPrompt(fixture, { ...settings, text_scale: 1.6 })).toContain(
      '- text_scale: 1.6',
    );
  });

  it('makes requests the proxy accepts, under the token budget', () => {
    const body = requestBody(fixture, settings, 'Bogstaverne er for små');
    const result = sanitize(body);
    expect(result.ok).toBe(true);
    if (result.ok) expect(estimateTokens(result.request)).toBeLessThan(2500);
  });
});

describe('cases', () => {
  it('has about 30 cases in English and Danish with unique ids', () => {
    expect(cases.length).toBeGreaterThanOrEqual(30);
    expect(new Set(cases.map((c) => c.id)).size).toBe(cases.length);
    expect(cases.some((c) => c.lang === 'da')).toBe(true);
    expect(cases.filter((c) => c.kind === 'offtopic').length).toBeGreaterThanOrEqual(3);
    expect(cases.filter((c) => c.kind === 'impossible').length).toBeGreaterThanOrEqual(3);
    expect(cases.filter((c) => c.kind === 'vague').length).toBeGreaterThanOrEqual(2);
  });

  it('expects only settings the app has', () => {
    const ids = new Set(fixture.settings.map((s) => s.id));
    for (const c of cases) {
      for (const id of [...(c.expect ?? []), ...Object.keys(c.settings ?? {})]) {
        expect(ids.has(id), `${c.id}: ${id}`).toBe(true);
      }
    }
  });
});

describe('checkCall', () => {
  it('accepts a valid call', () => {
    expect(
      checkCall(fixture, settings, call('set_button_scale', {
        value: 1.3, heuristic: 'near-miss-buttons', rationale: 'x',
      })),
    ).toMatchObject({ ok: true, setting: 'button_scale', from: 1, to: 1.3, outOfRange: false });
  });

  it('flags out-of-range values and clamps them', () => {
    expect(
      checkCall(fixture, settings, call('set_text_scale', {
        value: 10, heuristic: 'text-zoom', rationale: 'x',
      })),
    ).toMatchObject({ ok: true, to: 2, outOfRange: true });
  });

  it.each([
    [call('set_volume', { value: 1, heuristic: 'text-zoom' }), 'unknown_tool'],
    [{ name: 'set_text_scale', arguments: '{oops' }, 'bad_json'],
    [call('set_text_scale', { value: 1.2, heuristic: 'near-miss-buttons' }), 'unknown_heuristic'],
    [call('set_text_scale', { value: 'big', heuristic: 'text-zoom' }), 'bad_value'],
  ])('rejects %j', (c, reason) => {
    expect(checkCall(fixture, settings, c)).toEqual({ ok: false, reason });
  });
});

describe('score', () => {
  const buttons = cases.find((c) => c.id === 'en-buttons-hit')!;
  const tooBig = cases.find((c) => c.id === 'en-too-big')!;
  const weather = cases.find((c) => c.id === 'en-weather')!;
  const vague = cases.find((c) => c.id === 'en-too-small')!;

  it('counts the right setting in the right direction', () => {
    const good = score(fixture, buttons, answer({
      calls: [call('set_touch_target_scale', { value: 1.2, heuristic: 'missed-taps-touch-area', rationale: 'x' })],
    }));
    expect(good).toMatchObject({ correct: true, validCalls: true });

    const wrongWay = score(fixture, tooBig, answer({
      calls: [call('set_text_scale', { value: 1.8, heuristic: 'text-zoom', rationale: 'x' })],
    }));
    expect(wrongWay.correct).toBe(false);

    const rightWay = score(fixture, tooBig, answer({
      calls: [call('set_text_scale', { value: 1.4, heuristic: 'too-big-crowded', rationale: 'x' })],
    }));
    expect(rightWay.correct).toBe(true);
  });

  it('wants no tool call for off-topic requests', () => {
    expect(score(fixture, weather, answer({ text: 'I can only change sizes.' })).correct).toBe(true);
    expect(
      score(fixture, weather, answer({
        calls: [call('set_text_scale', { value: 1.2, heuristic: 'text-zoom', rationale: 'x' })],
      })).correct,
    ).toBe(false);
  });

  it('accepts a question for a vague request', () => {
    const r = score(fixture, vague, answer({ text: 'Which part is too small?' }));
    expect(r).toMatchObject({ correct: true, clarified: true });
  });

  it('a failed request is not answered', () => {
    const r = score(fixture, buttons, answer({ status: 503, errorCode: 'ASSIST_FALLBACK', provider: null }));
    expect(r.answered).toBe(false);
  });
});

describe('summarize', () => {
  it('reports rates and latency per provider', () => {
    const buttons = cases.find((c) => c.id === 'en-buttons-hit')!;
    const results = [
      score(fixture, buttons, answer({
        latencyMs: 400,
        calls: [call('set_button_scale', { value: 1.2, heuristic: 'near-miss-buttons', rationale: 'x' })],
      })),
      score(fixture, buttons, answer({
        latencyMs: 800,
        calls: [call('set_button_scale', { value: 9, heuristic: 'nope', rationale: 'x' })],
      })),
      score(fixture, buttons, answer({ status: 503, errorCode: 'ASSIST_FALLBACK' })),
    ];
    const s = summarize(results);
    expect(s.answered).toBe(2);
    expect(s.validToolCallRate).toBe(0.5);
    expect(s.correctSettingRate).toBe(0.5);
    expect(s.invalidProposals).toEqual([{ id: 'en-buttons-hit', reasons: ['unknown_heuristic'] }]);
    expect(s.latencyMsByProvider.groq).toEqual({ n: 2, median: 400, p90: 800, max: 800 });
    expect(s.notAnswered).toEqual([{ id: 'en-buttons-hit', error: 'ASSIST_FALLBACK' }]);
  });

  it('percentile', () => {
    expect(percentile([5, 1, 3], 50)).toBe(3);
    expect(percentile([], 50)).toBeNull();
  });
});
