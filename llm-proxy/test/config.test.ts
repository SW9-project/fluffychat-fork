// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import {
  ConfigError,
  loadConfig,
  parseProviders,
  resolveProviders,
} from '../src/config.js';

const env = {
  GROQ_API_KEY: 'gsk_test',
  SYNAPSE_URL: 'http://synapse:8008/',
  HOMESERVER_NAME: 'example.org',
  LOG_SALT: '0123456789abcdef',
};

describe('config', () => {
  it('loads the shipped providers.json with defaults', () => {
    const config = loadConfig(env);
    expect(config.providers.map((p) => p.name)).toEqual(['groq']);
    expect(config.providers[0]!.apiKey).toBe('gsk_test');
    expect(config.synapseUrl).toBe('http://synapse:8008');
    expect(config.rateLimitPerMin).toBe(10);
    expect(config.studyLogging).toBe(false);
    expect(config.tokenBudgetWarn).toBe(2500);
  });

  it('skips providers that are disabled or have no key', () => {
    const providers = parseProviders({
      providers: [
        { name: 'a', baseUrl: 'https://a/v1', model: 'm', apiKeyEnv: 'A_KEY' },
        {
          name: 'b',
          baseUrl: 'https://b/v1',
          model: 'm',
          apiKeyEnv: 'B_KEY',
          enabled: false,
        },
        { name: 'c', baseUrl: 'https://c/v1/', model: 'm', apiKeyEnv: 'C_KEY' },
      ],
    });
    const resolved = resolveProviders(providers, { B_KEY: 'x', C_KEY: 'y' });
    expect(resolved.map((p) => p.name)).toEqual(['c']);
    expect(resolved[0]!.baseUrl).toBe('https://c/v1');
  });

  it('refuses to start without a key, a salt or Synapse', () => {
    expect(() => loadConfig({ ...env, GROQ_API_KEY: '' })).toThrow(ConfigError);
    expect(() => loadConfig({ ...env, LOG_SALT: 'short' })).toThrow(ConfigError);
    expect(() => loadConfig({ ...env, SYNAPSE_URL: undefined })).toThrow(
      ConfigError,
    );
  });

  it('reads the study logging flag', () => {
    expect(loadConfig({ ...env, STUDY_LOGGING: 'true' }).studyLogging).toBe(true);
  });
});
