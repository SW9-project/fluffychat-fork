// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createHash } from 'node:crypto';
import type { Fetch } from './providers.js';

/**
 * Checks a Matrix OpenID token against our Synapse.
 *
 * The app asks its homeserver for a short-lived OpenID token
 * (POST /_matrix/client/v3/user/{userId}/openid/request_token) and sends it
 * as a bearer token. That token can only prove who the user is; unlike an
 * access token it cannot read or send messages, so the proxy never holds
 * anything that could act as the user. Synapse answers
 * GET /_matrix/federation/v1/openid/userinfo with the user ID, and only
 * users on our own homeserver are accepted.
 */

export type AuthResult =
  | { ok: true; userId: string }
  | { ok: false; reason: 'missing' | 'invalid' | 'foreign' | 'unavailable' };

export interface VerifierOptions {
  synapseUrl: string;
  homeserverName: string;
  cacheTtlMs: number;
  fetch?: Fetch;
  now?: () => number;
  timeoutMs?: number;
  /** Upper bound on cached tokens, so the cache cannot grow without limit. */
  maxEntries?: number;
}

const tokenShape = /^[A-Za-z0-9._~+/=-]{8,512}$/;

export function bearerToken(header: string | undefined): string | undefined {
  const match = /^Bearer\s+(\S+)$/i.exec(header?.trim() ?? '');
  return match?.[1];
}

export class OpenIdVerifier {
  private readonly cache = new Map<string, { userId: string; expires: number }>();
  private readonly fetchFn: Fetch;
  private readonly now: () => number;

  constructor(private readonly options: VerifierOptions) {
    this.fetchFn = options.fetch ?? fetch;
    this.now = options.now ?? Date.now;
  }

  async verify(token: string | undefined): Promise<AuthResult> {
    if (!token) return { ok: false, reason: 'missing' };
    if (!tokenShape.test(token)) return { ok: false, reason: 'invalid' };

    const key = createHash('sha256').update(token).digest('hex');
    const cached = this.cache.get(key);
    if (cached && cached.expires > this.now()) {
      return { ok: true, userId: cached.userId };
    }
    this.cache.delete(key);

    let response: Response;
    try {
      const url = new URL(
        '/_matrix/federation/v1/openid/userinfo',
        this.options.synapseUrl,
      );
      url.searchParams.set('access_token', token);
      response = await this.fetchFn(url, {
        signal: AbortSignal.timeout(this.options.timeoutMs ?? 5000),
      });
    } catch {
      return { ok: false, reason: 'unavailable' };
    }
    if (response.status === 401 || response.status === 403) {
      return { ok: false, reason: 'invalid' };
    }
    if (!response.ok) return { ok: false, reason: 'unavailable' };

    let sub: unknown;
    try {
      sub = ((await response.json()) as { sub?: unknown }).sub;
    } catch {
      return { ok: false, reason: 'unavailable' };
    }
    if (typeof sub !== 'string' || !sub.startsWith('@')) {
      return { ok: false, reason: 'invalid' };
    }
    if (!sub.endsWith(`:${this.options.homeserverName}`)) {
      return { ok: false, reason: 'foreign' };
    }

    if (this.options.cacheTtlMs > 0) {
      if (this.cache.size >= (this.options.maxEntries ?? 10_000)) {
        this.prune();
      }
      this.cache.set(key, {
        userId: sub,
        expires: this.now() + this.options.cacheTtlMs,
      });
    }
    return { ok: true, userId: sub };
  }

  private prune(): void {
    const now = this.now();
    for (const [key, entry] of this.cache) {
      if (entry.expires <= now) this.cache.delete(key);
    }
    // Still full: drop the oldest entries (Map keeps insertion order).
    const max = this.options.maxEntries ?? 10_000;
    for (const key of this.cache.keys()) {
      if (this.cache.size < max) break;
      this.cache.delete(key);
    }
  }
}
