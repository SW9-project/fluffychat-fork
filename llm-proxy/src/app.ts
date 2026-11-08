// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import Fastify, { type FastifyInstance, type FastifyReply } from 'fastify';
import { bearerToken, OpenIdVerifier } from './auth.js';
import type { ProxyConfig, ResolvedProvider } from './config.js';
import { hashUser, jsonLogger, type Logger } from './log.js';
import { callProvider, type Fetch } from './providers.js';
import { RateLimiter } from './rateLimit.js';
import { estimateTokens, sanitize } from './sanitize.js';

/**
 * Error codes the app understands. ASSIST_FALLBACK means "no remote model
 * answered, use the on-device model".
 */
export const errorCodes = {
  unauthorized: 'ASSIST_UNAUTHORIZED',
  authUnavailable: 'ASSIST_AUTH_UNAVAILABLE',
  rateLimited: 'ASSIST_RATE_LIMITED',
  badRequest: 'ASSIST_BAD_REQUEST',
  fallback: 'ASSIST_FALLBACK',
} as const;

export interface AppDeps {
  config: ProxyConfig;
  fetch?: Fetch;
  now?: () => number;
  logger?: Logger;
}

interface Attempt {
  provider: string;
  outcome: string;
  status: number | null;
  ms: number;
}

function sendError(
  reply: FastifyReply,
  status: number,
  code: string,
  message: string,
) {
  return reply.code(status).send({ error: { code, message } });
}

export function buildApp(deps: AppDeps): FastifyInstance {
  const { config } = deps;
  const fetchFn = deps.fetch ?? fetch;
  const now = deps.now ?? Date.now;
  const logger = deps.logger ?? jsonLogger();
  const verifier = new OpenIdVerifier({
    synapseUrl: config.synapseUrl,
    homeserverName: config.homeserverName,
    cacheTtlMs: config.authCacheTtlS * 1000,
    fetch: fetchFn,
    now,
  });
  const limiter = new RateLimiter(config.rateLimitPerMin, now);

  const app = Fastify({ logger: false, bodyLimit: 32 * 1024 });

  app.setErrorHandler((error: { statusCode?: number }, _request, reply) => {
    const status = error.statusCode ?? 500;
    if (status >= 400 && status < 500) {
      return sendError(reply, status, errorCodes.badRequest, 'Malformed request');
    }
    logger.log('error', 'internal_error', { status });
    return sendError(reply, 500, 'ASSIST_INTERNAL', 'Internal error');
  });

  app.get('/healthz', async () => ({ ok: true }));

  app.post('/v1/assist', async (request, reply) => {
    const started = now();

    const auth = await verifier.verify(bearerToken(request.headers.authorization));
    if (!auth.ok) {
      logger.log('warn', 'auth_rejected', { reason: auth.reason });
      return auth.reason === 'unavailable'
        ? sendError(reply, 503, errorCodes.authUnavailable, 'Cannot reach the homeserver')
        : sendError(reply, 401, errorCodes.unauthorized, 'Not signed in to our homeserver');
    }
    const user = hashUser(config.logSalt, auth.userId);

    const rate = limiter.take(auth.userId);
    if (!rate.allowed) {
      logger.log('warn', 'rate_limited', { user });
      reply.header('retry-after', String(rate.retryAfterS));
      return sendError(reply, 429, errorCodes.rateLimited, 'Too many requests, wait a minute');
    }

    const sanitized = sanitize(request.body);
    if (!sanitized.ok) {
      logger.log('warn', 'bad_request', { user, reason: sanitized.reason });
      return sendError(reply, 400, errorCodes.badRequest, sanitized.reason);
    }
    const body = sanitized.request;

    let providers: ResolvedProvider[] = config.providers;
    const forced = request.headers['x-assist-provider'];
    if (config.allowProviderOverride && typeof forced === 'string' && forced) {
      providers = config.providers.filter((p) => p.name === forced);
      if (providers.length === 0) {
        return sendError(reply, 400, errorCodes.badRequest, `Unknown provider ${forced}`);
      }
    }

    const estimated = estimateTokens(body);
    const attempts: Attempt[] = [];
    for (const provider of providers) {
      const attemptStart = now();
      const result = await callProvider(
        provider,
        body,
        { maxTokens: config.maxTokens, temperature: config.temperature },
        fetchFn,
      );
      const ms = now() - attemptStart;

      if (result.kind === 'ok') {
        const promptTokens = result.usage?.prompt_tokens ?? estimated;
        const record: Record<string, unknown> = {
          user,
          provider: provider.name,
          model: provider.model,
          latency_ms: now() - started,
          provider_ms: ms,
          prompt_tokens: result.usage?.prompt_tokens ?? null,
          completion_tokens: result.usage?.completion_tokens ?? null,
          estimated_tokens: estimated,
          tools_offered: body.tools.length,
          tools_called: (result.message.tool_calls ?? []).map((c) => c.function.name),
          answered_with_text: !result.message.tool_calls && !!result.message.content,
          failed_over: attempts,
        };
        if (config.studyLogging) {
          record.prompt = body.messages.filter((m) => m.role === 'user').at(-1)?.content;
        }
        logger.log('info', 'assist', record);
        if (promptTokens > config.tokenBudgetWarn) {
          logger.log('warn', 'token_budget_exceeded', {
            user,
            provider: provider.name,
            prompt_tokens: promptTokens,
            budget: config.tokenBudgetWarn,
          });
        }
        reply.header('x-assist-provider', provider.name);
        return {
          message: result.message,
          usage: result.usage,
          assist: { provider: provider.name, model: provider.model },
        };
      }

      attempts.push({ provider: provider.name, outcome: result.reason, status: result.status, ms });
      if (result.kind === 'fail') break;
    }

    logger.log('warn', 'assist_fallback', {
      user,
      latency_ms: now() - started,
      estimated_tokens: estimated,
      attempts,
    });
    return sendError(
      reply,
      503,
      errorCodes.fallback,
      'No online model answered; use the on-device model',
    );
  });

  return app;
}
