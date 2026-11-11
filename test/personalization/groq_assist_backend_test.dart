// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_backend.dart';
import 'package:fluffychat/personalization/assist/assist_chat_format.dart';
import 'package:fluffychat/personalization/assist/assist_prompt.dart';
import 'package:fluffychat/personalization/assist/assist_result.dart';
import 'package:fluffychat/personalization/assist/groq_assist_backend.dart';
import 'package:fluffychat/personalization/assist/prompt_redactor.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/settings_call_validator.dart';
import 'package:fluffychat/personalization/settings_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

const _key = 'gsk_test_secret_key_123';

AssistPromptTemplate _template() => AssistPromptTemplate.parse(
  File(AssistPromptTemplate.assetPath).readAsStringSync(),
);

final _heuristics = HeuristicsConfig.fromJson(
  jsonDecode(File('assets/personalization_heuristics.json').readAsStringSync()),
).heuristics;

Map<String, Object?> _choice(
  Map<String, Object?> message, {
  String finishReason = 'stop',
}) => {
  'id': 'chatcmpl-1',
  'choices': [
    {'index': 0, 'message': message, 'finish_reason': finishReason},
  ],
  'usage': {'prompt_tokens': 1400, 'completion_tokens': 40},
};

Map<String, Object?> _toolAnswer(String name, Map<String, Object?> args) =>
    _choice({
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        {
          'id': 'call_1',
          'type': 'function',
          'function': {'name': name, 'arguments': jsonEncode(args)},
        },
      ],
    }, finishReason: 'tool_calls');

final _validButtons = _toolAnswer('set_button_scale', {
  'value': 1.4,
  'heuristic': 'near-miss-buttons',
  'rationale': 'Bigger buttons are easier to hit.',
});

final _toolUseFailed = {
  'error': {
    'message': 'Failed to call a function.',
    'type': 'invalid_request_error',
    'code': 'tool_use_failed',
    'failed_generation': '<function=set_button_scale>{"value": big}',
  },
};

http.Response _json(
  int status,
  Object body, {
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

void main() {
  late List<http.Request> sent;

  GroqAssistBackend backend(
    FutureOr<http.Response> Function(http.Request request) handler, {
    Duration timeout = const Duration(seconds: 10),
    String? reasoningEffort,
    List<String> names = const [],
  }) {
    sent = [];
    return GroqAssistBackend(
      GroqConfig(
        apiKey: _key,
        model: 'openai/gpt-oss-20b',
        reasoningEffort: reasoningEffort,
      ),
      heuristics: () => _heuristics,
      loadTemplate: () async => _template(),
      redactor: PromptRedactor(knownNames: () => names),
      client: MockClient((request) async {
        sent.add(request);
        return handler(request);
      }),
      timeout: timeout,
    );
  }

  /// Answers the requests in order with [responses].
  GroqAssistBackend sequence(List<http.Response> responses) {
    var i = 0;
    return backend((_) => responses[i++]);
  }

  final settings = AccessibilitySettings.defaults.copyWith(
    ScaleCategory.button,
    1.2,
  );

  Map<String, Object?> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, Object?>;

  group('request', () {
    test(
      'sends only the model parameters, prompt, settings and tools',
      () async {
        final b = backend((_) => _json(200, _validButtons));
        await b.ask(AssistRequest('I keep missing the buttons', settings));

        final request = sent.single;
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://api.groq.com/openai/v1/chat/completions',
        );
        expect(request.headers['authorization'], 'Bearer $_key');
        final body = bodyOf(request);
        expect(
          body.keys,
          unorderedEquals([
            'model',
            'messages',
            'tools',
            'tool_choice',
            'temperature',
            'max_completion_tokens',
          ]),
        );
        expect(body['model'], 'openai/gpt-oss-20b');
        expect(body['tool_choice'], 'auto');

        final messages = (body['messages'] as List).cast<Map>();
        expect(messages.map((m) => m['role']), ['system', 'user']);
        expect(
          messages.every((m) => m.length == 2 && m.containsKey('content')),
          isTrue,
        );
        expect(messages.last['content'], 'I keep missing the buttons');
        expect(messages.first['content'], startsWith(_template().system));
        expect(messages.first['content'], contains('- button_scale: 1.2'));

        final tools = (body['tools'] as List).cast<Map>();
        expect(
          tools.map((t) => (t['function'] as Map)['name']),
          SettingsRegistry.all.map((s) => 'set_${s.id}'),
        );
      },
    );

    test('sends reasoning_effort only when it is configured', () async {
      final b = backend(
        (_) => _json(200, _validButtons),
        reasoningEffort: 'low',
      );
      await b.ask(AssistRequest('x', settings));
      expect(bodyOf(sent.single)['reasoning_effort'], 'low');
    });

    test('removes IDs, links and known names from every user text', () async {
      final b = backend(
        (_) => _json(200, _choice({'role': 'assistant', 'content': 'Okay.'})),
        names: ['Anna Jensen'],
      );
      await b.ask(
        AssistRequest(
          'the ones Anna sees, https://example.org/x',
          settings,
          previous: const AssistTurn(
            'it is too small, like @bob:example.org and Jensen said',
            'Which part is too small, Anna?',
          ),
        ),
      );
      final messages = (bodyOf(sent.single)['messages'] as List).cast<Map>();
      expect(messages.map((m) => m['role']), [
        'system',
        'user',
        'assistant',
        'user',
      ]);
      expect(
        messages[1]['content'],
        'it is too small, like [id] and [name] said',
      );
      expect(messages[2]['content'], 'Which part is too small, [name]?');
      expect(messages[3]['content'], 'the ones [name] sees, [link]');
    });
  });

  group('answers', () {
    test('validates a tool call into a proposal', () async {
      final b = backend(
        (_) => _json(
          200,
          _toolAnswer('set_button_scale', {
            'value': 9,
            'heuristic': 'near-miss-buttons',
            'rationale': 'Bigger buttons are easier to hit.',
          }),
        ),
      );
      final outcome = await b.ask(AssistRequest('buttons!', settings));
      final result = outcome.result as AssistProposal;
      expect(result.from, 1.2);
      expect(result.to, 2.0);
      expect(result.clamped, isTrue);
      expect(result.rationale, 'Bigger buttons are easier to hit.');
      expect(outcome.source.kind, AssistBackendKind.remote);
      expect(outcome.source.provider, 'groq');
      expect(outcome.source.model, 'openai/gpt-oss-20b');
      expect(outcome.timing!.inputTokens, 1400);
      expect(outcome.timing!.outputTokens, 40);
      expect(b.lastReport!.attempts, 1);
      expect(b.lastReport!.firstAttemptMalformed, isFalse);
    });

    test('turns a text answer into a message', () async {
      final b = backend(
        (_) => _json(
          200,
          _choice({
            'role': 'assistant',
            'content': '**Which** part is too small?',
          }),
        ),
      );
      final outcome = await b.ask(AssistRequest('too small', settings));
      expect(
        (outcome.result as AssistMessage).text,
        'Which part is too small?',
      );
    });

    test('an empty answer is no suggestion, without asking again', () async {
      final b = backend(
        (_) => _json(200, _choice({'role': 'assistant', 'content': '  '})),
      );
      final outcome = await b.ask(AssistRequest('x', settings));
      expect(
        (outcome.result as AssistNoSuggestion).reason,
        RejectionReason.noCall,
      );
      expect(sent, hasLength(1));
    });

    test('a value equal to the current one is not retried', () async {
      final b = backend(
        (_) => _json(
          200,
          _toolAnswer('set_button_scale', {
            'value': 1.2,
            'heuristic': 'near-miss-buttons',
            'rationale': 'x',
          }),
        ),
      );
      final outcome = await b.ask(AssistRequest('x', settings));
      expect(
        (outcome.result as AssistNoSuggestion).reason,
        RejectionReason.noChange,
      );
      expect(sent, hasLength(1));
    });
  });

  group('malformed tool calls are asked once more', () {
    test('an unknown tool, then a valid call', () async {
      final b = sequence([
        _json(200, _toolAnswer('delete_all_chats', {})),
        _json(200, _validButtons),
      ]);
      final outcome = await b.ask(AssistRequest('x', settings));
      expect(outcome.result, isA<AssistProposal>());
      expect(sent, hasLength(2));
      final retrySystem =
          ((bodyOf(sent[1])['messages'] as List).first as Map)['content'];
      expect(retrySystem, endsWith(AssistChatFormat.retryHint));
      final firstSystem =
          ((bodyOf(sent[0])['messages'] as List).first as Map)['content'];
      expect(firstSystem, isNot(contains(AssistChatFormat.retryHint)));
      expect(b.lastReport!.attempts, 2);
      expect(b.lastReport!.firstAttemptMalformed, isTrue);
      expect(outcome.timing!.inputTokens, 2800);
    });

    test('Groq tool_use_failed, then a valid call', () async {
      final b = sequence([
        _json(400, _toolUseFailed),
        _json(200, _validButtons),
      ]);
      expect(
        (await b.ask(AssistRequest('x', settings))).result,
        isA<AssistProposal>(),
      );
      expect(sent, hasLength(2));
    });

    test('a cut-off answer without a tool call', () async {
      final b = sequence([
        _json(
          200,
          _choice({
            'role': 'assistant',
            'content': 'I think',
          }, finishReason: 'length'),
        ),
        _json(200, _validButtons),
      ]);
      expect(
        (await b.ask(AssistRequest('x', settings))).result,
        isA<AssistProposal>(),
      );
      expect(sent, hasLength(2));
    });

    test('gives up kindly after the second malformed answer', () async {
      final b = sequence([
        _json(400, _toolUseFailed),
        _json(
          200,
          _toolAnswer('set_button_scale', {
            'value': 'big',
            'heuristic': 'near-miss-buttons',
            'rationale': 'x',
          }),
        ),
        _json(200, _validButtons),
      ]);
      final outcome = await b.ask(AssistRequest('x', settings));
      expect(
        (outcome.result as AssistNoSuggestion).reason,
        RejectionReason.invalidArguments,
      );
      expect(sent, hasLength(2));
    });
  });

  group('errors', () {
    Future<AssistBackendUnavailable> failure(GroqAssistBackend b) async {
      try {
        await b.ask(AssistRequest('x', settings));
      } on AssistBackendUnavailable catch (e) {
        return e;
      }
      fail('expected AssistBackendUnavailable');
    }

    test('429 reports the wait and is never retried here', () async {
      final e = await failure(
        backend(
          (_) => _json(
            429,
            {
              'error': {'code': 'rate_limit_exceeded'},
            },
            headers: {'retry-after': '7'},
          ),
        ),
      );
      expect(e.rateLimited, isTrue);
      expect(e.retryAfter, const Duration(seconds: 7));
      expect(sent, hasLength(1));
    });

    test('429 without retry-after has no wait', () async {
      final e = await failure(backend((_) => _json(429, {})));
      expect(e.rateLimited, isTrue);
      expect(e.retryAfter, isNull);
    });

    for (final status in [500, 502, 503, 498]) {
      test('$status is a server error', () async {
        final e = await failure(backend((_) => _json(status, {})));
        expect(e.reason, 'server_error');
        expect(e.network, isFalse);
        expect(sent, hasLength(1));
      });
    }

    test('a rejected key', () async {
      final e = await failure(
        backend(
          (_) => _json(401, {
            'error': {'code': 'invalid_api_key'},
          }),
        ),
      );
      expect(e.reason, 'key_rejected');
    });

    test('an unknown model', () async {
      final e = await failure(
        backend(
          (_) => _json(404, {
            'error': {'code': 'model_not_found'},
          }),
        ),
      );
      expect(e.reason, 'rejected_model_not_found');
    });

    test('network error', () async {
      final e = await failure(
        backend((_) => throw const SocketException('down')),
      );
      expect(e.network, isTrue);
      expect(e.reason, 'network');
    });

    test('timeout', () async {
      final e = await failure(
        backend(
          (_) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 20),
        ),
      );
      expect(e.network, isTrue);
      expect(e.reason, 'timeout');
    });

    test('a body that is not JSON', () async {
      final e = await failure(backend((_) => http.Response('<html>', 200)));
      expect(e.reason, 'bad_response');
    });

    test('the key never appears in errors or logs', () async {
      Logs().outputEvents.clear();
      final handlers = <FutureOr<http.Response> Function(http.Request)>[
        (_) => _json(401, {
          'error': {'code': 'invalid_api_key', 'message': 'Invalid API Key'},
        }),
        (_) => _json(404, {
          'error': {'code': 'model_not_found'},
        }),
        (_) => _json(429, {}, headers: {'retry-after': '3'}),
        (_) => _json(503, {}),
        (_) => throw http.ClientException('failed', Uri.parse('https://x')),
        (_) => http.Response('nope', 200),
      ];
      final errors = <String>[];
      for (final handler in handlers) {
        final b = backend(handler);
        try {
          await b.ask(AssistRequest('x', settings));
        } on AssistBackendUnavailable catch (e) {
          errors.add(e.toString());
        }
        errors.add(b.toString());
      }
      expect(errors, hasLength(handlers.length * 2));
      final logs = Logs().outputEvents.map((e) => e.toFormattedString());
      for (final text in [...errors, ...logs]) {
        expect(text, isNot(contains(_key)));
      }
      expect(
        GroqConfig(apiKey: _key, model: 'm').toString(),
        isNot(contains(_key)),
      );
    });
  });

  group('GroqConfig', () {
    test('a key and a model make a configuration', () {
      final r = GroqConfig.resolve(
        key: ' $_key ',
        model: 'openai/gpt-oss-20b',
        reasoningEffort: 'low',
      );
      expect(r.missing, isNull);
      expect(r.config!.apiKey, _key);
      expect(r.config!.reasoningEffort, 'low');
    });

    test('an empty reasoning effort is not sent', () {
      final r = GroqConfig.resolve(key: _key, model: 'm');
      expect(r.config!.reasoningEffort, isNull);
    });

    test('says what is missing', () {
      expect(
        GroqConfig.resolve(key: '', model: 'm').missing,
        startsWith('GROQ_API_KEY not set'),
      );
      expect(
        GroqConfig.resolve(key: GroqConfig.placeholderKey, model: 'm').missing,
        startsWith('GROQ_API_KEY not set'),
      );
      expect(
        GroqConfig.resolve(key: _key, model: ' ').missing,
        startsWith('GROQ_MODEL not set'),
      );
      expect(
        GroqConfig.resolve(key: '', model: '').missing,
        startsWith('GROQ_API_KEY and GROQ_MODEL not set'),
      );
      expect(GroqConfig.resolve(key: '', model: '').config, isNull);
    });

    test('env.example.json has the placeholder key and a model', () {
      final example =
          jsonDecode(File('env.example.json').readAsStringSync()) as Map;
      expect(
        example.keys,
        unorderedEquals([
          'GROQ_API_KEY',
          'GROQ_MODEL',
          'GROQ_REASONING_EFFORT',
        ]),
      );
      expect(example['GROQ_API_KEY'], GroqConfig.placeholderKey);
      final r = GroqConfig.resolve(
        key: example['GROQ_API_KEY'],
        model: example['GROQ_MODEL'],
      );
      expect(r.config, isNull);
      expect(r.missing, startsWith('GROQ_API_KEY not set'));
    });
  });

  group('headers', () {
    test('parses Groq durations', () {
      expect(
        GroqRateLimit.parseDuration('7.66s'),
        const Duration(milliseconds: 7660),
      );
      expect(
        GroqRateLimit.parseDuration('2m59.56s'),
        const Duration(minutes: 2, milliseconds: 59560),
      );
      expect(
        GroqRateLimit.parseDuration('1h2m'),
        const Duration(hours: 1, minutes: 2),
      );
      expect(
        GroqRateLimit.parseDuration('120ms'),
        const Duration(milliseconds: 120),
      );
      expect(GroqRateLimit.parseDuration('soon'), isNull);
      expect(GroqRateLimit.parseDuration('3s later'), isNull);
      expect(GroqRateLimit.parseDuration(null), isNull);
    });

    test('reads the rate-limit headers', () async {
      final b = backend(
        (_) => _json(
          200,
          _validButtons,
          headers: {
            'x-ratelimit-remaining-requests': '998',
            'x-ratelimit-remaining-tokens': '6400',
            'x-ratelimit-reset-requests': '2m59.56s',
            'x-ratelimit-reset-tokens': '7.66s',
          },
        ),
      );
      await b.ask(AssistRequest('x', settings));
      final limit = b.lastReport!.rateLimit!;
      expect(limit.remainingRequests, 998);
      expect(limit.remainingTokens, 6400);
      expect(limit.resetTokens, const Duration(milliseconds: 7660));
    });

    test('parses retry-after seconds only', () {
      expect(
        GroqAssistBackend.parseRetryAfter('7'),
        const Duration(seconds: 7),
      );
      expect(
        GroqAssistBackend.parseRetryAfter('0.5'),
        const Duration(milliseconds: 500),
      );
      expect(GroqAssistBackend.parseRetryAfter(''), isNull);
      expect(GroqAssistBackend.parseRetryAfter('-1'), isNull);
      expect(
        GroqAssistBackend.parseRetryAfter('Wed, 21 Oct 2026 07:28:00 GMT'),
        isNull,
      );
    });
  });
}
