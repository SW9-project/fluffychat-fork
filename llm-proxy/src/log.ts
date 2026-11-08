// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createHmac } from 'node:crypto';

/**
 * JSON-lines logging. Records carry a keyed hash of the user ID, never the
 * ID itself, and never the prompt text, tokens or keys. The prompt is added
 * only when STUDY_LOGGING is on (see README: the study's consent must cover
 * it).
 */

export type Level = 'info' | 'warn' | 'error';

export interface Logger {
  log(level: Level, event: string, fields?: Record<string, unknown>): void;
}

export function jsonLogger(
  write: (line: string) => void = (line) => process.stdout.write(`${line}\n`),
  now: () => Date = () => new Date(),
): Logger {
  return {
    log(level, event, fields = {}) {
      write(JSON.stringify({ ts: now().toISOString(), level, event, ...fields }));
    },
  };
}

export function hashUser(salt: string, userId: string): string {
  return createHmac('sha256', salt).update(userId).digest('hex').slice(0, 16);
}
