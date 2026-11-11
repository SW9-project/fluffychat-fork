// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../heuristics/heuristic.dart';
import '../model/settings_call_validator.dart';
import '../model/settings_intent_model.dart';
import 'assist_backend.dart';
import 'assist_chat_format.dart';
import 'assist_prompt.dart';
import 'assist_result.dart';
import 'prompt_redactor.dart';

/// Groq settings from `--dart-define-from-file=env.json`. See the README
/// section "AI Assist (development only)".
@immutable
class GroqConfig {
  final String apiKey;
  final String model;

  /// Sent as `reasoning_effort` when set; only some models accept it.
  final String? reasoningEffort;

  const GroqConfig({
    required this.apiKey,
    required this.model,
    this.reasoningEffort,
  });

  /// The key in `env.example.json`, treated as no key.
  static const placeholderKey = 'paste-your-gsk-key-here';

  static const _key = String.fromEnvironment('GROQ_API_KEY');
  static const _model = String.fromEnvironment('GROQ_MODEL');
  static const _reasoningEffort = String.fromEnvironment(
    'GROQ_REASONING_EFFORT',
  );

  /// The configuration this build was made with, or a developer-facing
  /// [missing] text when the key or the model is not set.
  static ({GroqConfig? config, String? missing}) fromEnvironment() =>
      resolve(key: _key, model: _model, reasoningEffort: _reasoningEffort);

  /// Checks [key] and [model] as [fromEnvironment] does; the evaluation
  /// script uses it with the values from env.json.
  static ({GroqConfig? config, String? missing}) resolve({
    required String key,
    required String model,
    String reasoningEffort = '',
  }) {
    final k = key.trim();
    final m = model.trim();
    final missing = [
      if (k.isEmpty || k == placeholderKey) 'GROQ_API_KEY',
      if (m.isEmpty) 'GROQ_MODEL',
    ];
    if (missing.isNotEmpty) {
      return (
        config: null,
        missing:
            '${missing.join(' and ')} not set. Copy env.example.json to '
            'env.json, fill it in and run with '
            '--dart-define-from-file=env.json. Using the on-device model.',
      );
    }
    final effort = reasoningEffort.trim();
    return (
      config: GroqConfig(
        apiKey: k,
        model: m,
        reasoningEffort: effort.isEmpty ? null : effort,
      ),
      missing: null,
    );
  }

  /// Never shows the key.
  @override
  String toString() => 'GroqConfig(model: $model)';
}

/// Groq's rate-limit headers from the last response. Per Groq's docs the
/// request numbers are per day and the token numbers per minute.
@immutable
class GroqRateLimit {
  final int? remainingRequests;
  final int? remainingTokens;
  final Duration? resetRequests;
  final Duration? resetTokens;

  const GroqRateLimit({
    this.remainingRequests,
    this.remainingTokens,
    this.resetRequests,
    this.resetTokens,
  });

  static GroqRateLimit fromHeaders(Map<String, String> headers) =>
      GroqRateLimit(
        remainingRequests: int.tryParse(
          headers['x-ratelimit-remaining-requests'] ?? '',
        ),
        remainingTokens: int.tryParse(
          headers['x-ratelimit-remaining-tokens'] ?? '',
        ),
        resetRequests: parseDuration(headers['x-ratelimit-reset-requests']),
        resetTokens: parseDuration(headers['x-ratelimit-reset-tokens']),
      );

  static final _part = RegExp(r'(\d+(?:\.\d+)?)(ms|h|m|s)');

  /// Parses Groq's durations such as `7.66s`, `2m59.56s` or `1h2m`.
  static Duration? parseDuration(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    var micros = 0.0;
    var consumed = 0;
    for (final match in _part.allMatches(text)) {
      if (match.start != consumed) return null;
      consumed = match.end;
      final value = double.parse(match[1]!);
      micros +=
          value *
          switch (match[2]!) {
            'h' => Duration.microsecondsPerHour,
            'm' => Duration.microsecondsPerMinute,
            's' => Duration.microsecondsPerSecond,
            _ => Duration.microsecondsPerMillisecond,
          };
    }
    if (consumed != text.length) return null;
    return Duration(microseconds: micros.round());
  }
}

/// What happened during the last [GroqAssistBackend.ask], for the evaluation
/// script. Holds no text.
@immutable
class GroqAskReport {
  /// HTTP requests made: 1, or 2 after a malformed tool call.
  final int attempts;

  /// The first answer had a tool call that could not be used.
  final bool firstAttemptMalformed;

  /// The request's size by our own estimate, before it was sent.
  final int estimatedTokens;

  /// Groq's token counts, summed over all attempts.
  final int promptTokens;
  final int completionTokens;

  final GroqRateLimit? rateLimit;

  const GroqAskReport({
    required this.attempts,
    required this.firstAttemptMalformed,
    required this.estimatedTokens,
    required this.promptTokens,
    required this.completionTokens,
    this.rateLimit,
  });
}

/// The online assistant: asks Groq's OpenAI-compatible chat-completions API
/// directly from the phone.
///
/// TODO(dev-only): this sends an API key that is compiled into the app with
/// `--dart-define-from-file=env.json`. Anyone who has the app can extract
/// it, and every user shares its free-tier limits. It is for development and
/// our research study only. Before any public release, replace this one class
/// with an [AssistBackend] that talks to our own proxy, which holds the key
/// (see `llm-proxy/` and the README section "AI Assist (development
/// only)"). [AssistChatFormat] stays the same, so nothing else changes.
///
/// What is sent: the system prompt from `assets/assist/heuristics.md`, the
/// current setting values, the tool schemas from the settings registry and
/// the user's Assist text (plus at most one earlier question and answer),
/// after [PromptRedactor] removed IDs, links, e-mail addresses and known
/// names. Nothing else from the app is sent; see [AssistChatFormat.body].
///
/// Failures:
/// - A malformed tool call (Groq's `tool_use_failed`, or one our validator
///   cannot use) is asked once more, then the user gets a friendly message.
/// - HTTP 429 throws [AssistBackendUnavailable] with `rateLimited` and the
///   `retry-after` wait. This class never waits or retries a 429 itself.
/// - No network, a timeout, 5xx, 498, a rejected key or a request Groq
///   refuses throw [AssistBackendUnavailable], so the on-device model can
///   answer instead.
class GroqAssistBackend extends AssistBackend {
  static final endpoint = Uri.parse(
    'https://api.groq.com/openai/v1/chat/completions',
  );

  /// The same values the proxy used.
  static const temperature = 0.2;
  static const maxCompletionTokens = 300;

  final GroqConfig _config;
  final List<Heuristic> Function() heuristics;
  final Future<AssistPromptTemplate> Function() loadTemplate;
  final PromptRedactor redactor;
  final http.Client _client;
  final Duration timeout;

  GroqAssistBackend(
    this._config, {
    required this.heuristics,
    Future<AssistPromptTemplate> Function()? loadTemplate,
    this.redactor = const PromptRedactor(),
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : loadTemplate = loadTemplate ?? AssistPromptTemplate.load,
       _client = client ?? http.Client();

  String get model => _config.model;

  static final ValueNotifier<ModelStatus> _ready = ValueNotifier(
    const ModelStatus(ModelState.ready),
  );

  @override
  ValueListenable<ModelStatus> get status => _ready;

  @override
  Future<void> prepare() async {}

  AssistPromptTemplate? _template;

  /// Diagnostics of the last [ask] that got an answer, for the evaluation.
  GroqAskReport? lastReport;

  @override
  Future<AssistOutcome> ask(AssistRequest request) async {
    final template = _template ??= await loadTemplate();
    final prompt = AssistPromptBuilder.build(template, request.settings);
    final heuristics = this.heuristics();
    final watch = Stopwatch()..start();

    var attempts = 0;
    var promptTokens = 0;
    var completionTokens = 0;
    var firstMalformed = false;
    var estimated = 0;
    GroqRateLimit? rateLimit;
    late final AssistResult result;

    for (var retry = false; ; retry = true) {
      final body = jsonEncode(_body(prompt, request, retry: retry));
      final estimate = AssistPrompt.estimateTokens(body);
      if (!retry) estimated = AssistPromptBuilder.checkBudget(estimate);
      attempts++;
      final answer = await _post(body);
      rateLimit = answer.rateLimit;
      promptTokens += answer.promptTokens;
      completionTokens += answer.completionTokens;

      final message = answer.message;
      final candidate = message == null
          ? null
          : AssistChatFormat.interpret(
              message,
              prompt: prompt,
              template: template,
              heuristics: heuristics,
              request: request,
            );
      final malformed =
          candidate == null ||
          answer.truncated ||
          AssistChatFormat.isMalformed(candidate);
      if (!malformed) {
        result = candidate;
        break;
      }
      if (retry) {
        // Asked twice: say so kindly instead of guessing.
        result = const AssistNoSuggestion(RejectionReason.invalidArguments);
        break;
      }
      firstMalformed = true;
    }
    watch.stop();

    lastReport = GroqAskReport(
      attempts: attempts,
      firstAttemptMalformed: firstMalformed,
      estimatedTokens: estimated,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      rateLimit: rateLimit,
    );
    return AssistOutcome(
      result,
      AssistSource(AssistBackendKind.remote, provider: 'groq', model: model),
      timing: ModelTiming(
        totalMs: watch.elapsedMilliseconds,
        backend: 'remote',
        inputTokens: promptTokens,
        outputTokens: completionTokens,
      ),
    );
  }

  Map<String, Object?> _body(
    AssistPrompt prompt,
    AssistRequest request, {
    required bool retry,
  }) => {
    'model': _config.model,
    ...AssistChatFormat.body(prompt, request, redactor, retry: retry),
    'temperature': temperature,
    'max_completion_tokens': maxCompletionTokens,
    'reasoning_effort': ?_config.reasoningEffort,
  };

  /// Sends one request. Returns the assistant message, or a null message
  /// when Groq says the model's tool call was malformed; throws
  /// [AssistBackendUnavailable] for everything the on-device model should
  /// answer instead.
  Future<_Answer> _post(String body) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${_config.apiKey}',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AssistBackendUnavailable('timeout', network: true);
    } catch (_) {
      // DNS and socket errors. The error itself is not logged, so nothing
      // about the request can end up in the logs.
      throw const AssistBackendUnavailable('network', network: true);
    }

    final rateLimit = GroqRateLimit.fromHeaders(response.headers);
    final json = _decode(response.body);
    final code = (json?['error'] as Map?)?['code'];
    final status = response.statusCode;

    if (status == 200) {
      final choice = (json?['choices'] as List?)?.firstOrNull;
      final message = choice is Map ? choice['message'] : null;
      if (message is! Map) {
        throw const AssistBackendUnavailable('bad_response');
      }
      final usage = json?['usage'] as Map?;
      return _Answer(
        message,
        rateLimit: rateLimit,
        truncated:
            choice['finish_reason'] == 'length' &&
            AssistChatFormat.toolCalls(message).isEmpty,
        promptTokens: (usage?['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (usage?['completion_tokens'] as num?)?.toInt() ?? 0,
      );
    }
    if (status == 400 && code == 'tool_use_failed') {
      return _Answer(null, rateLimit: rateLimit);
    }
    if (status == 429) {
      throw AssistBackendUnavailable(
        'rate_limited',
        rateLimited: true,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
      );
    }
    final reason = switch (status) {
      401 || 403 => 'key_rejected',
      498 || >= 500 => 'server_error',
      _ => 'rejected_${code is String ? code : status}',
    };
    if (kDebugMode && status < 500 && status != 498) {
      Logs().w(
        reason == 'key_rejected'
            ? 'Groq rejected the API key (HTTP $status). Check GROQ_API_KEY '
                  'in env.json.'
            : 'Groq refused the Assist request (HTTP $status, $reason). '
                  'Check GROQ_MODEL and GROQ_REASONING_EFFORT in env.json.',
      );
    }
    throw AssistBackendUnavailable(reason);
  }

  /// Groq sends whole seconds; anything else is treated as unknown.
  static Duration? parseRetryAfter(String? raw) {
    final seconds = double.tryParse(raw?.trim() ?? '');
    if (seconds == null || !seconds.isFinite || seconds < 0) return null;
    return Duration(milliseconds: (seconds * 1000).ceil());
  }

  static Map<String, Object?>? _decode(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? json : null;
    } on FormatException {
      return null;
    }
  }

  @override
  void dispose() => _client.close();
}

class _Answer {
  /// Null when Groq reported a malformed tool call.
  final Map? message;
  final bool truncated;
  final int promptTokens;
  final int completionTokens;
  final GroqRateLimit rateLimit;

  const _Answer(
    this.message, {
    required this.rateLimit,
    this.truncated = false,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });
}
