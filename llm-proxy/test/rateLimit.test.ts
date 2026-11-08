// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { RateLimiter } from '../src/rateLimit.js';

describe('RateLimiter', () => {
  it('allows the limit per minute and then refuses', () => {
    let time = 0;
    const limiter = new RateLimiter(10, () => time);
    for (let i = 0; i < 10; i++) {
      time = i * 1000;
      expect(limiter.take('@alice:example.org').allowed).toBe(true);
    }
    time = 10_000;
    expect(limiter.take('@alice:example.org')).toEqual({
      allowed: false,
      retryAfterS: 50,
    });
  });

  it('counts each user on their own', () => {
    const limiter = new RateLimiter(1, () => 0);
    expect(limiter.take('@alice:example.org').allowed).toBe(true);
    expect(limiter.take('@bob:example.org').allowed).toBe(true);
    expect(limiter.take('@alice:example.org').allowed).toBe(false);
  });

  it('frees a slot once the oldest request is a minute old', () => {
    let time = 0;
    const limiter = new RateLimiter(2, () => time);
    limiter.take('u');
    time = 30_000;
    limiter.take('u');
    expect(limiter.take('u').allowed).toBe(false);
    time = 60_001;
    expect(limiter.take('u').allowed).toBe(true);
    expect(limiter.take('u').allowed).toBe(false);
  });

  it('does not count refused requests', () => {
    let time = 0;
    const limiter = new RateLimiter(1, () => time);
    limiter.take('u');
    time = 59_000;
    limiter.take('u');
    time = 60_001;
    expect(limiter.take('u').allowed).toBe(true);
  });
});
