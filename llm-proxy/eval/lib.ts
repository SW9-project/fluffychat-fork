// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/**
 * Evaluation helpers. The fixture holds the app's real system prompt and
 * tools (exported by test/personalization/assist_eval_fixture_test.dart),
 * and the validation rules mirror lib/personalization/assist/assist_validator.dart.
 */

export interface SettingDef {
  id: string;
  min: number;
  max: number;
  step: number;
  default: number;
}

export interface ToolJson {
  type: 'function';
  function: {
    name: string;
    description: string;
    parameters: {
      properties: { heuristic: { enum: string[] } } & Record<string, unknown>;
    };
  };
}

export interface Fixture {
  settingsHeader: string;
  systemPrefix: string;
  systemWithDefaults: string;
  settings: SettingDef[];
  tools: ToolJson[];
}

export const fixturePath = fileURLToPath(
  new URL('./fixtures/assist_request.json', import.meta.url),
);

export function loadFixture(path = fixturePath): Fixture {
  return JSON.parse(readFileSync(path, 'utf8')) as Fixture;
}

export type Settings = Record<string, number>;

export function defaults(fixture: Fixture): Settings {
  return Object.fromEntries(fixture.settings.map((s) => [s.id, s.default]));
}

/** Dart prints doubles with at least one decimal (1.0, 1.25). */
export function dartDouble(value: number): string {
  return Number.isInteger(value) ? value.toFixed(1) : String(value);
}

/** The system prompt the app would send with [settings]. */
export function systemPrompt(fixture: Fixture, settings: Settings): string {
  const offered = new Set(fixture.tools.map((t) => t.function.name));
  const lines = fixture.settings
    .filter((s) => offered.has(`set_${s.id}`))
    .map((s) => `- ${s.id}: ${dartDouble(settings[s.id] ?? s.default)}`);
  return `${fixture.systemPrefix}\n${lines.join('\n')}`;
}

export function requestBody(fixture: Fixture, settings: Settings, prompt: string) {
  return {
    messages: [
      { role: 'system', content: systemPrompt(fixture, settings) },
      { role: 'user', content: prompt },
    ],
    tools: fixture.tools,
    tool_choice: 'auto',
  };
}

export interface RawCall {
  name: string;
  arguments: string;
}

export type CallCheck =
  | {
      ok: true;
      setting: string;
      from: number;
      to: number;
      raw: number;
      outOfRange: boolean;
      heuristic: string;
      rationale: string | null;
    }
  | {
      ok: false;
      reason: 'unknown_tool' | 'bad_json' | 'unknown_heuristic' | 'bad_value';
    };

function snap(value: number, s: SettingDef): number {
  const clamped = Math.min(s.max, Math.max(s.min, value));
  const steps = Math.round((clamped - s.min) / s.step);
  return Number(Math.min(s.max, s.min + steps * s.step).toFixed(2));
}

/** Same checks as AssistValidator, without clamping hiding the problem. */
export function checkCall(fixture: Fixture, settings: Settings, call: RawCall): CallCheck {
  const tool = fixture.tools.find((t) => t.function.name === call.name.trim());
  const setting = fixture.settings.find((s) => `set_${s.id}` === call.name.trim());
  if (!tool || !setting) return { ok: false, reason: 'unknown_tool' };
  let args: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(call.arguments || '{}');
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return { ok: false, reason: 'bad_json' };
    }
    args = parsed as Record<string, unknown>;
  } catch {
    return { ok: false, reason: 'bad_json' };
  }
  const heuristic = typeof args.heuristic === 'string' ? args.heuristic.trim() : '';
  if (!tool.function.parameters.properties.heuristic.enum.includes(heuristic)) {
    return { ok: false, reason: 'unknown_heuristic' };
  }
  const raw =
    typeof args.value === 'number'
      ? args.value
      : typeof args.value === 'string'
        ? Number(args.value.trim())
        : Number.NaN;
  if (!Number.isFinite(raw)) return { ok: false, reason: 'bad_value' };
  const from = settings[setting.id] ?? setting.default;
  return {
    ok: true,
    setting: setting.id,
    from,
    to: snap(raw, setting),
    raw,
    outOfRange: raw < setting.min - 1e-9 || raw > setting.max + 1e-9,
    heuristic,
    rationale: typeof args.rationale === 'string' ? args.rationale : null,
  };
}

export type CaseKind = 'setting' | 'vague' | 'offtopic' | 'impossible';

export interface EvalCase {
  id: string;
  lang: 'en' | 'da';
  kind: CaseKind;
  prompt: string;
  /** Acceptable settings for 'setting' and 'vague' cases. */
  expect?: string[];
  direction?: 'up' | 'down';
  /** Settings that differ from the defaults before the request. */
  settings?: Settings;
}

export interface Answer {
  status: number;
  provider: string | null;
  latencyMs: number;
  promptTokens: number | null;
  calls: RawCall[];
  text: string | null;
  errorCode: string | null;
}

export interface Scored {
  id: string;
  lang: string;
  kind: CaseKind;
  provider: string | null;
  latencyMs: number;
  promptTokens: number | null;
  answered: boolean;
  calledTool: boolean;
  /** Every call the model made passed validation. */
  validCalls: boolean;
  invalidReasons: string[];
  outOfRange: boolean;
  setting: string | null;
  to: number | null;
  correct: boolean;
  clarified: boolean;
  text: string | null;
  errorCode: string | null;
}

export function score(fixture: Fixture, c: EvalCase, answer: Answer): Scored {
  const settings = { ...defaults(fixture), ...c.settings };
  const checks = answer.calls.map((call) => checkCall(fixture, settings, call));
  const first = checks.find((x) => x.ok);
  const invalidReasons = checks.flatMap((x) => (x.ok ? [] : [x.reason]));
  const calledTool = answer.calls.length > 0;
  const clarified = !calledTool && !!answer.text?.trim();

  const directionOk = (x: Extract<CallCheck, { ok: true }>) =>
    c.direction === undefined ||
    (c.direction === 'up' ? x.to > x.from : x.to < x.from);
  const settingOk =
    first?.ok === true &&
    (c.expect?.includes(first.setting) ?? false) &&
    directionOk(first);

  let correct: boolean;
  switch (c.kind) {
    case 'setting':
      correct = settingOk;
      break;
    case 'vague':
      // A short question is the preferred answer; a fitting change is fine too.
      correct = clarified || settingOk;
      break;
    case 'offtopic':
    case 'impossible':
      correct = answer.status === 200 && !calledTool;
      break;
  }

  return {
    id: c.id,
    lang: c.lang,
    kind: c.kind,
    provider: answer.provider,
    latencyMs: answer.latencyMs,
    promptTokens: answer.promptTokens,
    answered: answer.status === 200,
    calledTool,
    validCalls: calledTool && invalidReasons.length === 0,
    invalidReasons,
    outOfRange: checks.some((x) => x.ok && x.outOfRange),
    setting: first?.ok ? first.setting : null,
    to: first?.ok ? first.to : null,
    correct,
    clarified,
    text: answer.text,
    errorCode: answer.errorCode,
  };
}

export function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, index)]!;
}

const rate = (n: number, d: number) => (d === 0 ? null : Number((n / d).toFixed(3)));

export function summarize(results: Scored[]) {
  const answered = results.filter((r) => r.answered);
  const withCalls = answered.filter((r) => r.calledTool);
  const settingCases = answered.filter((r) => r.kind === 'setting');
  const noToolCases = answered.filter((r) => r.kind === 'offtopic' || r.kind === 'impossible');
  const vague = answered.filter((r) => r.kind === 'vague');

  const byProvider: Record<string, { n: number; median: number | null; p90: number | null; max: number | null }> = {};
  for (const provider of new Set(answered.map((r) => r.provider ?? 'unknown'))) {
    const ms = answered.filter((r) => (r.provider ?? 'unknown') === provider).map((r) => r.latencyMs);
    byProvider[provider] = {
      n: ms.length,
      median: percentile(ms, 50),
      p90: percentile(ms, 90),
      max: ms.length ? Math.max(...ms) : null,
    };
  }

  const byLang: Record<string, { n: number; correct: number | null }> = {};
  for (const lang of new Set(answered.map((r) => r.lang))) {
    const rs = answered.filter((r) => r.lang === lang);
    byLang[lang] = { n: rs.length, correct: rate(rs.filter((r) => r.correct).length, rs.length) };
  }

  const tokens = answered.flatMap((r) => (r.promptTokens === null ? [] : [r.promptTokens]));
  return {
    cases: results.length,
    answered: answered.length,
    notAnswered: results
      .filter((r) => !r.answered)
      .map((r) => ({ id: r.id, error: r.errorCode })),
    validToolCallRate: rate(withCalls.filter((r) => r.validCalls).length, withCalls.length),
    toolCallRateWhenExpected: rate(settingCases.filter((r) => r.calledTool).length, settingCases.length),
    correctSettingRate: rate(settingCases.filter((r) => r.correct).length, settingCases.length),
    vagueHandledRate: rate(vague.filter((r) => r.correct).length, vague.length),
    vagueClarifiedRate: rate(vague.filter((r) => r.clarified).length, vague.length),
    noToolWhenNotApplicableRate: rate(noToolCases.filter((r) => r.correct).length, noToolCases.length),
    invalidProposals: withCalls.filter((r) => !r.validCalls).map((r) => ({ id: r.id, reasons: r.invalidReasons })),
    outOfRangeProposals: answered.filter((r) => r.outOfRange).map((r) => r.id),
    overallCorrectRate: rate(answered.filter((r) => r.correct).length, answered.length),
    byLanguage: byLang,
    latencyMsByProvider: byProvider,
    promptTokens: {
      median: percentile(tokens, 50),
      max: tokens.length ? Math.max(...tokens) : null,
    },
  };
}
