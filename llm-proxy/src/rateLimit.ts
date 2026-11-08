// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Sliding one-minute window per user. Free-tier limits belong to our
 * provider account and every user shares them, so one user must not be able
 * to use them up. Kept in memory: the proxy runs as a single container.
 */

export type RateDecision =
  | { allowed: true; remaining: number }
  | { allowed: false; retryAfterS: number };

export class RateLimiter {
  private readonly hits = new Map<string, number[]>();

  constructor(
    private readonly perMinute: number,
    private readonly now: () => number = Date.now,
    private readonly windowMs = 60_000,
  ) {}

  take(user: string): RateDecision {
    const now = this.now();
    const since = now - this.windowMs;
    const recent = (this.hits.get(user) ?? []).filter((t) => t > since);
    if (recent.length >= this.perMinute) {
      this.hits.set(user, recent);
      const retryAfterMs = recent[0]! + this.windowMs - now;
      return { allowed: false, retryAfterS: Math.max(1, Math.ceil(retryAfterMs / 1000)) };
    }
    recent.push(now);
    this.hits.set(user, recent);
    if (this.hits.size > 10_000) this.prune(since);
    return { allowed: true, remaining: this.perMinute - recent.length };
  }

  private prune(since: number): void {
    for (const [user, times] of this.hits) {
      if (!times.some((t) => t > since)) this.hits.delete(user);
    }
  }
}
