// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Evaluates the online Assist model on Groq with generated requests.
///
/// It sends every case through the app's own [GroqAssistBackend.ask], so the
/// prompt, the tool schemas, the redaction, the single retry and the
/// validator are exactly the app's. Run it from the repo root:
///
/// ```bash
/// flutter test tool/assist_eval.dart
/// ```
///
/// It reads `GROQ_API_KEY`, `GROQ_MODEL` and `GROQ_REASONING_EFFORT` from
/// `env.json` (see `env.example.json`). It goes through the Flutter test
/// runner because the settings registry uses Flutter; plain `flutter test`
/// only runs `test/`, so this never runs by accident.
///
/// Options, all optional:
///
/// ```bash
/// flutter test tool/assist_eval.dart --dart-define=EVAL_ONLY=en-buttons-hit,da-too-big --dart-define=EVAL_LIMIT=5 --dart-define=EVAL_TPM=8000 --dart-define=EVAL_RPM=30
/// ```
///
/// The free tier's limits are shared by everyone using the key, so the
/// script paces itself by tokens per minute (EVAL_TPM), not only by requests
/// per minute (EVAL_RPM), and follows Groq's own rate-limit headers. A full
/// run uses roughly 33 x 1,800 = 60,000 of the 200,000 daily tokens of
/// openai/gpt-oss-20b. Results go to `build/assist_eval/<time>.json`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_backend.dart';
import 'package:fluffychat/personalization/assist/assist_chat_format.dart';
import 'package:fluffychat/personalization/assist/assist_prompt.dart';
import 'package:fluffychat/personalization/assist/assist_result.dart';
import 'package:fluffychat/personalization/assist/groq_assist_backend.dart';
import 'package:fluffychat/personalization/assist/prompt_redactor.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/settings_call_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

enum Kind { setting, vague, offTopic, impossible }

enum Direction { up, down }

/// One generated request. [expect] lists every setting that would be a
/// reasonable answer; [settings] are the values before the request.
class EvalCase {
  final String id;
  final String lang;
  final Kind kind;
  final String prompt;
  final List<String> expect;
  final Direction direction;
  final Map<String, double> settings;

  const EvalCase(
    this.id,
    this.lang,
    this.kind,
    this.prompt, {
    this.expect = const [],
    this.direction = Direction.up,
    this.settings = const {},
  });
}

const _text = 'text_scale';
const _input = 'input_text_scale';
const _button = 'button_scale';
const _touch = 'touch_target_scale';
const _avatar = 'avatar_scale';
const _buttons = [_button, _touch];
const _anySize = [_text, _input, _button, _touch, _avatar];
const _seeing = [_text, _input, _button, _avatar];

/// Generated requests: specific and vague complaints in English and Danish,
/// the "too big" direction, an out-of-range wish, off-topic requests and
/// requests for things the app cannot change. To add a setting to the
/// registry, add cases for it here.
const cases = [
  // English: specific
  EvalCase(
    'en-buttons-hit',
    'en',
    Kind.setting,
    "I can't hit the buttons",
    expect: _buttons,
  ),
  EvalCase(
    'en-letters-small',
    'en',
    Kind.setting,
    'the letters are too small',
    expect: [_text],
  ),
  EvalCase(
    'en-wrong-thing',
    'en',
    Kind.setting,
    'I keep pressing the wrong thing',
    expect: _buttons,
  ),
  EvalCase(
    'en-who-wrote',
    'en',
    Kind.setting,
    "I can't see who sent the message",
    expect: [_avatar],
  ),
  EvalCase(
    'en-typing',
    'en',
    Kind.setting,
    "When I type I can't read my own words",
    expect: [_input, _text],
  ),
  EvalCase(
    'en-pictures-tiny',
    'en',
    Kind.setting,
    'The little pictures of people are tiny',
    expect: [_avatar],
  ),
  EvalCase(
    'en-send-small',
    'en',
    Kind.setting,
    'The send button is so small that I miss it',
    expect: _buttons,
  ),
  EvalCase(
    'en-icons-larger',
    'en',
    Kind.setting,
    'Can you make the icons larger?',
    expect: [_button],
  ),
  EvalCase(
    'en-too-big',
    'en',
    Kind.setting,
    'The writing is far too big now, I have to scroll all the time',
    expect: [_text],
    direction: Direction.down,
    settings: {_text: 1.6},
  ),
  EvalCase(
    'en-text-smaller',
    'en',
    Kind.setting,
    'make the text a bit smaller please',
    expect: [_text],
    direction: Direction.down,
    settings: {_text: 1.4},
  ),
  // English: vague. A short question back counts as correct, so does a
  // fitting change.
  EvalCase(
    'en-eyes-bad',
    'en',
    Kind.vague,
    'My eyes are not so good anymore',
    expect: _seeing,
  ),
  EvalCase(
    'en-too-small',
    'en',
    Kind.vague,
    "It's too small",
    expect: _anySize,
  ),

  // Danish: specific
  EvalCase(
    'da-buttons-hit',
    'da',
    Kind.setting,
    'Jeg kan ikke ramme knapperne',
    expect: _buttons,
  ),
  EvalCase(
    'da-letters-small',
    'da',
    Kind.setting,
    'Bogstaverne er for små',
    expect: [_text],
  ),
  EvalCase(
    'da-wrong-thing',
    'da',
    Kind.setting,
    'Jeg kommer hele tiden til at trykke forkert',
    expect: _buttons,
  ),
  EvalCase(
    'da-who-wrote',
    'da',
    Kind.setting,
    'Jeg kan ikke se, hvem der har skrevet',
    expect: [_avatar],
  ),
  EvalCase(
    'da-typing',
    'da',
    Kind.setting,
    'Teksten jeg selv skriver er svær at læse',
    expect: [_input, _text],
  ),
  EvalCase(
    'da-avatars',
    'da',
    Kind.setting,
    'Profilbillederne er alt for små',
    expect: [_avatar],
  ),
  EvalCase(
    'da-icons-larger',
    'da',
    Kind.setting,
    'Gør ikonerne større',
    expect: [_button],
  ),
  EvalCase(
    'da-buttons-see',
    'da',
    Kind.setting,
    'Knapperne er svære at se',
    expect: [_button],
  ),
  EvalCase(
    'da-too-big',
    'da',
    Kind.setting,
    'Teksten er blevet alt for stor',
    expect: [_text],
    direction: Direction.down,
    settings: {_text: 1.6},
  ),
  EvalCase(
    'da-text-smaller',
    'da',
    Kind.setting,
    'Kan du gøre skriften lidt mindre?',
    expect: [_text],
    direction: Direction.down,
    settings: {_text: 1.3},
  ),
  // Danish: vague
  EvalCase('da-eyes-bad', 'da', Kind.vague, 'Jeg ser dårligt', expect: _seeing),
  EvalCase(
    'da-too-small',
    'da',
    Kind.vague,
    'Det er for småt',
    expect: _anySize,
  ),

  // Out of range: should still pick text; the value gets clamped.
  EvalCase(
    'en-ten-times',
    'en',
    Kind.setting,
    'Make the text ten times bigger',
    expect: [_text],
  ),

  // Off-topic
  EvalCase(
    'en-weather',
    'en',
    Kind.offTopic,
    "What's the weather like tomorrow?",
  ),
  EvalCase('en-joke', 'en', Kind.offTopic, 'Tell me a joke'),
  EvalCase(
    'da-message-daughter',
    'da',
    Kind.offTopic,
    'Skriv til min datter, at jeg kommer klokken tre',
  ),
  EvalCase(
    'da-weather',
    'da',
    Kind.offTopic,
    'Hvordan bliver vejret i morgen?',
  ),

  // Impossible: there is no setting for it
  EvalCase(
    'en-read-aloud',
    'en',
    Kind.impossible,
    'Read my messages out loud to me',
  ),
  EvalCase(
    'en-dark-mode',
    'en',
    Kind.impossible,
    'Switch the app to dark mode',
  ),
  EvalCase('da-brighter', 'da', Kind.impossible, 'Gør skærmen lysere'),
  EvalCase(
    'da-read-aloud',
    'da',
    Kind.impossible,
    'Kan du læse beskederne højt for mig?',
  ),
];

/// One case's outcome, scored.
class Scored {
  final EvalCase c;
  final AssistResult? result;
  final String? error;
  final int latencyMs;
  final GroqAskReport? report;

  Scored(this.c, this.result, {this.error, this.latencyMs = 0, this.report});

  bool get answered => result != null;

  /// The final answer was a tool call (usable or not).
  bool get calledTool => switch (result) {
    AssistProposal() || AssistAtLimit() => true,
    AssistNoSuggestion(:final reason) => reason != RejectionReason.noCall,
    _ => false,
  };

  bool get invalid => result != null && AssistChatFormat.isMalformed(result!);

  bool get validCall => calledTool && !invalid;

  bool get outOfRange => switch (result) {
    AssistProposal(:final clamped) => clamped,
    _ => false,
  };

  String? get setting => switch (result) {
    AssistProposal(:final category) ||
    AssistAtLimit(:final category) => category.id,
    _ => null,
  };

  Direction? get direction => switch (result) {
    AssistProposal(:final from, :final to) =>
      to > from ? Direction.up : Direction.down,
    _ => null,
  };

  bool get clarified => result is AssistMessage;

  bool get rightSetting =>
      setting != null &&
      c.expect.contains(setting) &&
      (direction == null || direction == c.direction);

  bool get correct => switch (c.kind) {
    Kind.setting => rightSetting,
    Kind.vague => rightSetting || clarified,
    Kind.offTopic || Kind.impossible => answered && !calledTool,
  };

  String get summary => switch (result) {
    AssistProposal(:final category, :final from, :final to, :final clamped) =>
      '${category.id} $from -> $to${clamped ? ' (clamped)' : ''}',
    AssistAtLimit(:final category) => '${category.id} at limit',
    AssistNoSuggestion(:final reason) => 'no suggestion (${reason.name})',
    AssistMessage(:final text) => 'says: "$text"',
    AssistUnavailable(:final reason) => 'unavailable (${reason.name})',
    null => 'error: $error',
  };

  Map<String, Object?> toJson() => {
    'id': c.id,
    'lang': c.lang,
    'kind': c.kind.name,
    'prompt': c.prompt,
    'answer': summary,
    'setting': setting,
    'direction': direction?.name,
    'called_tool': calledTool,
    'valid_call': validCall,
    'out_of_range': outOfRange,
    'first_attempt_malformed': report?.firstAttemptMalformed,
    'attempts': report?.attempts,
    'correct': correct,
    'latency_ms': latencyMs,
    'prompt_tokens': report?.promptTokens,
    'completion_tokens': report?.completionTokens,
    'estimated_tokens': report?.estimatedTokens,
  };
}

/// Paces requests by tokens and requests per minute, and by Groq's own
/// rate-limit headers when they say the minute's tokens are nearly gone.
class Throttle {
  final int tokensPerMinute;
  final int requestsPerMinute;
  final _sent = <(DateTime, int)>[];
  GroqRateLimit? _limit;
  DateTime? _limitAt;

  Throttle({required this.tokensPerMinute, required this.requestsPerMinute});

  static const _minute = Duration(minutes: 1);

  Future<void> before(int tokens) async {
    while (true) {
      final now = DateTime.now();
      _sent.removeWhere((s) => now.difference(s.$1) >= _minute);
      var wait = Duration.zero;
      Duration untilOldestLeaves() =>
          _sent.first.$1.add(_minute).difference(now);
      final used = _sent.fold(0, (sum, s) => sum + s.$2);
      if (_sent.isNotEmpty && used + tokens > tokensPerMinute) {
        wait = untilOldestLeaves();
      }
      if (_sent.length >= requestsPerMinute) {
        wait = _max(wait, untilOldestLeaves());
      }
      if (_sent.isNotEmpty) {
        // Spread requests evenly instead of bursting.
        final gap = Duration(milliseconds: 60000 ~/ requestsPerMinute);
        wait = _max(wait, _sent.last.$1.add(gap).difference(now));
      }
      final limit = _limit;
      final at = _limitAt;
      if (limit?.remainingTokens case final remaining?
          when remaining < tokens && at != null) {
        final reset = limit?.resetTokens ?? _minute;
        wait = _max(wait, at.add(reset).difference(now));
      }
      if (wait <= Duration.zero) return;
      if (wait > const Duration(seconds: 3)) {
        // ignore: avoid_print
        print(
          '  … waiting ${(wait.inMilliseconds / 1000).toStringAsFixed(1)} s '
          'for the per-minute token budget',
        );
      }
      await Future<void>.delayed(wait);
    }
  }

  void after(int tokens, GroqRateLimit? limit) {
    _sent.add((DateTime.now(), tokens));
    if (limit != null) {
      _limit = limit;
      _limitAt = DateTime.now();
    }
  }

  static Duration _max(Duration a, Duration b) => a > b ? a : b;
}

double? _rate(Iterable<Scored> all, bool Function(Scored) ok) {
  final list = all.toList();
  if (list.isEmpty) return null;
  return double.parse((list.where(ok).length / list.length).toStringAsFixed(3));
}

int? _percentile(List<int> values, double p) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  return sorted[min(sorted.length - 1, (p / 100 * sorted.length).floor())];
}

Map<String, Object?> summarize(List<Scored> results) {
  final answered = results.where((r) => r.answered).toList();
  final calls = answered.where((r) => r.calledTool);
  final specific = answered.where((r) => r.c.kind == Kind.setting);
  final vague = answered.where((r) => r.c.kind == Kind.vague);
  final noTool = answered.where(
    (r) => r.c.kind == Kind.offTopic || r.c.kind == Kind.impossible,
  );
  final latencies = [for (final r in answered) r.latencyMs];
  final tokens = [
    for (final r in answered)
      if (r.report case final report?) report.promptTokens,
  ];
  return {
    'cases': results.length,
    'answered': answered.length,
    'errors': results.length - answered.length,
    'validToolCallRate': _rate(calls, (r) => r.validCall),
    'firstAttemptMalformedRate': _rate(
      answered,
      (r) => r.report?.firstAttemptMalformed ?? false,
    ),
    'toolCallRateWhenExpected': _rate(specific, (r) => r.calledTool),
    'correctSettingRate': _rate(specific, (r) => r.rightSetting),
    'vagueHandledRate': _rate(vague, (r) => r.correct),
    'vagueClarifiedRate': _rate(vague, (r) => r.clarified),
    'noToolWhenNotApplicableRate': _rate(noTool, (r) => r.correct),
    'overallCorrectRate': _rate(answered, (r) => r.correct),
    'invalidProposals': [
      for (final r in answered)
        if (r.invalid || (r.report?.firstAttemptMalformed ?? false)) r.c.id,
    ],
    'outOfRangeProposals': [
      for (final r in answered)
        if (r.outOfRange) r.c.id,
    ],
    'byLanguage': {
      for (final lang in ['en', 'da'])
        lang: _rate(answered.where((r) => r.c.lang == lang), (r) => r.correct),
    },
    'latencyMs': {
      'average': latencies.isEmpty
          ? null
          : (latencies.reduce((a, b) => a + b) / latencies.length).round(),
      'median': _percentile(latencies, 50),
      'p90': _percentile(latencies, 90),
      'max': latencies.isEmpty ? null : latencies.reduce(max),
    },
    'promptTokens': {
      'median': _percentile(tokens, 50),
      'max': tokens.isEmpty ? null : tokens.reduce(max),
      'budget': AssistPromptBuilder.tokenBudget,
    },
    'totalTokensUsed': answered.fold<int>(
      0,
      (sum, r) =>
          sum +
          (r.report?.promptTokens ?? 0) +
          (r.report?.completionTokens ?? 0),
    ),
  };
}

AccessibilitySettings _settingsFor(EvalCase c) {
  var settings = AccessibilitySettings.defaults;
  for (final MapEntry(:key, :value) in c.settings.entries) {
    settings = settings.copyWith(
      ScaleCategory.values.firstWhere((s) => s.id == key),
      value,
    );
  }
  return settings;
}

// ignore: avoid_print
void _say(Object text) => print(text);

/// With `--dart-define=EVAL_DRY_RUN=true` nothing leaves the machine: a fake
/// Groq answers every "too small" case with a text-size call and everything
/// else with a sentence. It checks the scoring, the pacing and the report
/// without a key or any of the shared quota; the scores mean nothing.
const _dryRun = bool.fromEnvironment('EVAL_DRY_RUN');

http.Client _dryRunClient() => MockClient((request) async {
  final body = jsonDecode(request.body) as Map;
  final user = '${((body['messages'] as List).last as Map)['content']}';
  final bigger = RegExp(
    'small|tiny|larger|bigger|små|småt|større',
    caseSensitive: false,
  ).hasMatch(user);
  final message = bigger
      ? {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'set_text_scale',
                'arguments': jsonEncode({
                  'value': 1.2,
                  'heuristic': 'text-zoom',
                  'rationale': 'Bigger text is easier to read.',
                }),
              },
            },
          ],
        }
      : {'role': 'assistant', 'content': 'I can only change sizes.'};
  return http.Response(
    jsonEncode({
      'choices': [
        {'message': message, 'finish_reason': bigger ? 'tool_calls' : 'stop'},
      ],
      'usage': {
        'prompt_tokens': AssistPrompt.estimateTokens(request.body),
        'completion_tokens': 30,
      },
    }),
    200,
    headers: {
      'content-type': 'application/json',
      'x-ratelimit-remaining-requests': '999',
      'x-ratelimit-remaining-tokens': '7000',
      'x-ratelimit-reset-tokens': '7.5s',
    },
  );
});

/// The key and model from env.json, or null after saying what is missing.
GroqConfig? _readConfig() {
  if (_dryRun) {
    return const GroqConfig(apiKey: 'dry-run', model: 'dry-run');
  }
  final envFile = File('env.json');
  if (!envFile.existsSync()) {
    _say(
      'No env.json in ${Directory.current.path}. Copy env.example.json to '
      'env.json, add your Groq key and run again.',
    );
    return null;
  }
  final env = jsonDecode(envFile.readAsStringSync()) as Map;
  final (:config, :missing) = GroqConfig.resolve(
    key: '${env['GROQ_API_KEY'] ?? ''}',
    model: '${env['GROQ_MODEL'] ?? ''}',
    reasoningEffort: '${env['GROQ_REASONING_EFFORT'] ?? ''}',
  );
  if (config == null) _say('env.json: $missing');
  return config;
}

void main() {
  test('Groq Assist evaluation', () async {
    final config = _readConfig();
    if (config == null) return;

    const only = String.fromEnvironment('EVAL_ONLY');
    const limit = int.fromEnvironment('EVAL_LIMIT');
    final selected = [
      for (final c in cases)
        if (only.isEmpty || only.split(',').map((s) => s.trim()).contains(c.id))
          c,
    ].take(limit > 0 ? limit : cases.length).toList();

    final template = AssistPromptTemplate.parse(
      File(AssistPromptTemplate.assetPath).readAsStringSync(),
    );
    final heuristics = HeuristicsConfig.fromJson(
      jsonDecode(
        File('assets/personalization_heuristics.json').readAsStringSync(),
      ),
    ).heuristics;
    final backend = GroqAssistBackend(
      config,
      heuristics: () => heuristics,
      loadTemplate: () async => template,
      client: _dryRun ? _dryRunClient() : http.Client(),
      timeout: const Duration(seconds: 20),
    );
    final throttle = Throttle(
      tokensPerMinute: const int.fromEnvironment(
        'EVAL_TPM',
        defaultValue: 8000,
      ),
      requestsPerMinute: const int.fromEnvironment(
        'EVAL_RPM',
        defaultValue: 30,
      ),
    );

    _say('Evaluating ${config.model} on ${selected.length} cases.');
    final results = <Scored>[];
    for (final c in selected) {
      final request = AssistRequest(c.prompt, _settingsFor(c));
      // Our own estimate of the request plus the most it may answer.
      final prompt = AssistPromptBuilder.build(template, request.settings);
      final estimate =
          AssistPrompt.estimateTokens(
            jsonEncode(
              AssistChatFormat.body(prompt, request, const PromptRedactor()),
            ),
          ) +
          GroqAssistBackend.maxCompletionTokens;

      Scored? scored;
      for (var attempt = 1; scored == null; attempt++) {
        await throttle.before(estimate);
        try {
          final outcome = await backend.ask(request);
          final report = backend.lastReport;
          throttle.after(
            (report?.promptTokens ?? 0) + (report?.completionTokens ?? 0),
            report?.rateLimit,
          );
          scored = Scored(
            c,
            outcome.result,
            latencyMs: outcome.timing?.totalMs ?? 0,
            report: report,
          );
        } on AssistBackendUnavailable catch (e) {
          throttle.after(estimate, null);
          if (e.rateLimited && attempt == 1) {
            final wait = e.retryAfter ?? const Duration(seconds: 60);
            if (wait > const Duration(minutes: 5)) {
              scored = Scored(c, null, error: 'daily limit, retry in $wait');
              continue;
            }
            _say('  429: waiting ${wait.inSeconds} s, then trying once more');
            await Future<void>.delayed(wait);
            continue;
          }
          scored = Scored(c, null, error: e.reason);
        }
      }
      results.add(scored);
      _say(
        '${scored.correct ? 'ok  ' : 'MISS'} ${c.id.padRight(22)} '
        '${scored.summary}  (${scored.latencyMs} ms)',
      );
      if (scored.error?.startsWith('daily limit') ?? false) break;
    }
    backend.dispose();

    final summary = summarize(results);
    final rateLimit = backend.lastReport?.rateLimit;
    const encoder = JsonEncoder.withIndent('  ');
    _say('\n${encoder.convert(summary)}');
    if (rateLimit?.remainingRequests case final left?) {
      _say('Groq says $left requests are left today on this key.');
    }

    final dir = Directory('build/assist_eval')..createSync(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final out = File('${dir.path}/$stamp.json');
    out.writeAsStringSync(
      encoder.convert({
        'model': config.model,
        'reasoning_effort': config.reasoningEffort,
        'summary': summary,
        'results': [for (final r in results) r.toJson()],
      }),
    );
    _say('Wrote ${out.path}');
  }, timeout: Timeout.none);
}
