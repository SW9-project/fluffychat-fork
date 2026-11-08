// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import { buildApp } from './app.js';
import { ConfigError, loadConfig } from './config.js';
import { jsonLogger } from './log.js';

const logger = jsonLogger();

let config;
try {
  config = loadConfig();
} catch (e) {
  if (e instanceof ConfigError) {
    logger.log('error', 'config_error', { message: e.message });
    process.exit(1);
  }
  throw e;
}

const app = buildApp({ config, logger });

await app.listen({ host: '0.0.0.0', port: config.port });
logger.log('info', 'started', {
  port: config.port,
  providers: config.providers.map((p) => `${p.name}:${p.model}`),
  rate_limit_per_min: config.rateLimitPerMin,
  study_logging: config.studyLogging,
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    app.close().then(
      () => process.exit(0),
      () => process.exit(1),
    );
  });
}
