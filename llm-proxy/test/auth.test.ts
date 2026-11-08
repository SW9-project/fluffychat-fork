// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { bearerToken, OpenIdVerifier } from '../src/auth.js';
import type { Fetch } from '../src/providers.js';
import { json } from './helpers.js';

function synapse(users: Record<string, string>) {
  const calls: string[] = [];
  const fetchFn: Fetch = async (input) => {
    const url = new URL(String(input));
    calls.push(url.pathname);
    expect(url.origin).toBe('http://synapse.internal:8008');
    expect(url.pathname).toBe('/_matrix/federation/v1/openid/userinfo');
    const user = users[url.searchParams.get('access_token') ?? ''];
    return user
      ? json(200, { sub: user })
      : json(401, { errcode: 'M_UNKNOWN_TOKEN' });
  };
  return { fetchFn, calls };
}

function verifier(fetchFn: Fetch, now = () => 0) {
  return new OpenIdVerifier({
    synapseUrl: 'http://synapse.internal:8008',
    homeserverName: 'example.org',
    cacheTtlMs: 60_000,
    fetch: fetchFn,
    now,
  });
}

describe('bearerToken', () => {
  it('reads a bearer header', () => {
    expect(bearerToken('Bearer abcdefgh')).toBe('abcdefgh');
    expect(bearerToken('bearer  abcdefgh ')).toBe('abcdefgh');
    expect(bearerToken('Basic abc')).toBeUndefined();
    expect(bearerToken(undefined)).toBeUndefined();
  });
});

describe('OpenIdVerifier', () => {
  it('accepts a user on our homeserver', async () => {
    const { fetchFn } = synapse({ goodtoken: '@alice:example.org' });
    expect(await verifier(fetchFn).verify('goodtoken')).toEqual({
      ok: true,
      userId: '@alice:example.org',
    });
  });

  it('rejects a missing, malformed or unknown token', async () => {
    const { fetchFn, calls } = synapse({});
    const v = verifier(fetchFn);
    expect(await v.verify(undefined)).toEqual({ ok: false, reason: 'missing' });
    expect(await v.verify('short')).toEqual({ ok: false, reason: 'invalid' });
    expect(await v.verify('has spaces in it')).toEqual({ ok: false, reason: 'invalid' });
    expect(calls).toHaveLength(0);
    expect(await v.verify('unknowntoken')).toEqual({ ok: false, reason: 'invalid' });
  });

  it('rejects a user from another homeserver', async () => {
    const { fetchFn } = synapse({
      foreigntoken: '@mallory:example.org.evil.com',
      othertoken: '@bob:matrix.org',
    });
    const v = verifier(fetchFn);
    expect(await v.verify('foreigntoken')).toEqual({ ok: false, reason: 'foreign' });
    expect(await v.verify('othertoken')).toEqual({ ok: false, reason: 'foreign' });
  });

  it('reports Synapse being down separately from a bad token', async () => {
    const v = verifier(async () => {
      throw new TypeError('fetch failed');
    });
    expect(await v.verify('goodtoken')).toEqual({ ok: false, reason: 'unavailable' });
    const v2 = verifier(async () => json(502, {}));
    expect(await v2.verify('goodtoken')).toEqual({ ok: false, reason: 'unavailable' });
  });

  it('caches successful checks until the TTL ends', async () => {
    let time = 0;
    const { fetchFn, calls } = synapse({ goodtoken: '@alice:example.org' });
    const v = verifier(fetchFn, () => time);
    await v.verify('goodtoken');
    time = 59_000;
    await v.verify('goodtoken');
    expect(calls).toHaveLength(1);
    time = 61_000;
    await v.verify('goodtoken');
    expect(calls).toHaveLength(2);
  });

  it('does not cache rejections', async () => {
    const { fetchFn, calls } = synapse({});
    const v = verifier(fetchFn);
    await v.verify('unknowntoken');
    await v.verify('unknowntoken');
    expect(calls).toHaveLength(2);
  });
});
