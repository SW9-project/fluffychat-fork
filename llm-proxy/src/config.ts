// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/** One OpenAI-compatible provider, as written in config/providers.json. */
export interface ProviderConfig {
  name: string;
  /** Base URL up to and including the version, e.g. https://api.groq.com/openai/v1 */
  baseUrl: string;
  model: string;
  /** Name of the environment variable that holds this provider's API key. */
  apiKeyEnv: string;
  timeoutMs: number;
  enabled: boolean;
  /**
   * When set, sent as `parallel_tool_calls`. Leave it out for models that do
   * not support parallel tool calls at all (Groq's gpt-oss models).
   */
  parallelToolCalls?: boolean;
  /** Extra provider-specific body fields, e.g. Groq's `reasoning_effort`. */
  extraBody?: Record<string, unknown>;
}

/** A provider that is enabled and has its key. */
export interface ResolvedProvider extends ProviderConfig {
  apiKey: string;
}

export interface ProxyConfig {
  port: number;
  /** Synapse base URL as the proxy reaches it, e.g. http://synapse:8008 */
  synapseUrl: string;
  /** The homeserver's server_name; only users on it are accepted. */
  homeserverName: string;
  /** Secret salt for hashing user IDs in logs. */
  logSalt: string;
  rateLimitPerMin: number;
  authCacheTtlS: number;
  /** Opt-in for the user study: also log the user's Assist prompt. */
  studyLogging: boolean;
  tokenBudgetWarn: number;
  /** Lets the X-Assist-Provider header pick one provider (evaluation only). */
  allowProviderOverride: boolean;
  maxTokens: number;
  temperature: number;
  providers: ResolvedProvider[];
}

export class ConfigError extends Error {}

const defaultProvidersPath = fileURLToPath(
  new URL('../config/providers.json', import.meta.url),
);

type Env = Record<string, string | undefined>;

function required(env: Env, name: string): string {
  const value = env[name]?.trim();
  if (!value) throw new ConfigError(`${name} is required`);
  return value;
}

function integer(env: Env, name: string, fallback: number, min = 1): number {
  const raw = env[name]?.trim();
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min) {
    throw new ConfigError(`${name} must be an integer >= ${min}`);
  }
  return value;
}

function flag(env: Env, name: string): boolean {
  return ['1', 'true', 'yes', 'on'].includes(
    (env[name] ?? '').trim().toLowerCase(),
  );
}

export function parseProviders(json: unknown): ProviderConfig[] {
  const list = (json as { providers?: unknown })?.providers;
  if (!Array.isArray(list)) {
    throw new ConfigError('providers.json needs a "providers" array');
  }
  return list.map((p, i) => {
    const where = `providers[${i}]`;
    if (typeof p !== 'object' || p === null) {
      throw new ConfigError(`${where} must be an object`);
    }
    const o = p as Record<string, unknown>;
    for (const key of ['name', 'baseUrl', 'model', 'apiKeyEnv']) {
      if (typeof o[key] !== 'string' || !(o[key] as string).trim()) {
        throw new ConfigError(`${where}.${key} must be a non-empty string`);
      }
    }
    const baseUrl = (o.baseUrl as string).replace(/\/+$/, '');
    if (!/^https?:\/\//.test(baseUrl)) {
      throw new ConfigError(`${where}.baseUrl must be an http(s) URL`);
    }
    return {
      name: o.name as string,
      baseUrl,
      model: o.model as string,
      apiKeyEnv: o.apiKeyEnv as string,
      timeoutMs: typeof o.timeoutMs === 'number' ? o.timeoutMs : 8000,
      enabled: o.enabled !== false,
      parallelToolCalls:
        typeof o.parallelToolCalls === 'boolean'
          ? o.parallelToolCalls
          : undefined,
      extraBody:
        typeof o.extraBody === 'object' && o.extraBody !== null
          ? (o.extraBody as Record<string, unknown>)
          : undefined,
    };
  });
}

/** Providers that are enabled and whose key variable is set, in order. */
export function resolveProviders(
  providers: ProviderConfig[],
  env: Env,
): ResolvedProvider[] {
  return providers.flatMap((p) => {
    const apiKey = env[p.apiKeyEnv]?.trim();
    return p.enabled && apiKey ? [{ ...p, apiKey }] : [];
  });
}

export function loadConfig(
  env: Env = process.env,
  providersPath = env.PROVIDERS_FILE || defaultProvidersPath,
): ProxyConfig {
  const providers = resolveProviders(
    parseProviders(JSON.parse(readFileSync(providersPath, 'utf8'))),
    env,
  );
  if (providers.length === 0) {
    throw new ConfigError(
      'No provider is enabled with an API key. Set GROQ_API_KEY (see .env.example).',
    );
  }
  const logSalt = required(env, 'LOG_SALT');
  if (logSalt.length < 16) {
    throw new ConfigError('LOG_SALT must be at least 16 characters');
  }
  const synapseUrl = required(env, 'SYNAPSE_URL').replace(/\/+$/, '');
  if (!/^https?:\/\//.test(synapseUrl)) {
    throw new ConfigError('SYNAPSE_URL must be an http(s) URL');
  }
  return {
    port: integer(env, 'PORT', 8080),
    synapseUrl,
    homeserverName: required(env, 'HOMESERVER_NAME'),
    logSalt,
    rateLimitPerMin: integer(env, 'RATE_LIMIT_PER_MIN', 10),
    authCacheTtlS: integer(env, 'AUTH_CACHE_TTL_S', 60, 0),
    studyLogging: flag(env, 'STUDY_LOGGING'),
    tokenBudgetWarn: integer(env, 'TOKEN_BUDGET_WARN', 2500),
    allowProviderOverride: flag(env, 'ALLOW_PROVIDER_OVERRIDE'),
    maxTokens: integer(env, 'MAX_TOKENS', 300),
    temperature: 0.2,
    providers,
  };
}
