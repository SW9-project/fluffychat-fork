// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_backend.dart';
import 'package:fluffychat/personalization/assist/assist_prompt.dart';
import 'package:fluffychat/personalization/assist/assist_result.dart';
import 'package:fluffychat/personalization/assist/remote_assist_backend.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/settings_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AssistPromptTemplate _template() => AssistPromptTemplate.parse(
  File(AssistPromptTemplate.assetPath).readAsStringSync(),
);

final _heuristics = HeuristicsConfig.fromJson(
  jsonDecode(File('assets/personalization_heuristics.json').readAsStringSync()),
).heuristics;

Map<String, Object?> _toolAnswer(String name, Map<String, Object?> args) => {
  'message': {
    'role': 'assistant',
    'content': null,
    'tool_calls': [
      {
        'id': 'call_1',
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(args)},
      },
    ],
  },
  'usage': {'prompt_tokens': 1400, 'completion_tokens': 40},
  'assist': {'provider': 'groq', 'model': 'openai/gpt-oss-20b'},
};

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> sent;
  late int tokenRequests;

  RemoteAssistBackend backend(
    FutureOr<http.Response> Function(http.Request request) handler, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    sent = [];
    tokenRequests = 0;
    return RemoteAssistBackend(
      endpoint: Uri.parse('https://matrix.example.org/_assist/v1/assist'),
      token: OpenIdTokenSource(() async {
        tokenRequests++;
        return (
          token: 'openid-$tokenRequests',
          expiresIn: const Duration(hours: 1),
        );
      }),
      heuristics: () => _heuristics,
      loadTemplate: () async => _template(),
      client: MockClient((request) async {
        sent.add(request);
        return handler(request);
      }),
      timeout: timeout,
    );
  }

  final settings = AccessibilitySettings.defaults.copyWith(
    ScaleCategory.button,
    1.2,
  );

  group('request', () {
    test('sends only the system prompt, the prompt and the tools', () async {
      final b = backend(
        (_) => _json(
          200,
          _toolAnswer('set_button_scale', {
            'value': 1.4,
            'heuristic': 'near-miss-buttons',
            'rationale': 'Bigger buttons are easier to hit.',
          }),
        ),
      );
      await b.ask(AssistRequest('I keep missing the buttons', settings));

      final request = sent.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/_assist/v1/assist');
      expect(request.headers['authorization'], 'Bearer openid-1');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body.keys, unorderedEquals(['messages', 'tools', 'tool_choice']));

      final messages = (body['messages'] as List).cast<Map>();
      expect(messages.map((m) => m['role']), ['system', 'user']);
      expect(
        messages.every(
          (m) =>
              m.keys.toSet().containsAll(['role', 'content']) && m.length == 2,
        ),
        isTrue,
      );
      expect(messages.last['content'], 'I keep missing the buttons');
      expect(messages.first['content'], contains('- button_scale: 1.2'));

      final tools = (body['tools'] as List).cast<Map>();
      expect(
        tools.map((t) => (t['function'] as Map)['name']),
        SettingsRegistry.all.map((s) => 'set_${s.id}'),
      );
    });

    test('removes Matrix IDs, links and e-mail addresses from the prompt', () {
      expect(
        RemoteAssistBackend.redact(
          'Like in the chat with @anna:example.org in #family:example.org '
          'and !abc123:example.org, see https://example.org/x or '
          'mxc://example.org/abc, mail anna@example.org',
        ),
        'Like in the chat with [id] in [id] and [id], see [link] or [link], '
        'mail [email]',
      );
      expect(
        RemoteAssistBackend.redact('Make the text bigger! At 10:30 #1'),
        'Make the text bigger! At 10:30 #1',
      );
    });

    test('sends one earlier question and answer, redacted', () async {
      final b = backend(
        (_) => _json(200, {
          'message': {'role': 'assistant', 'content': 'Okay.'},
        }),
      );
      await b.ask(
        AssistRequest(
          'the ones at the bottom',
          settings,
          previous: const AssistTurn(
            'it is too small, like @bob:example.org said',
            'Which part is too small?',
          ),
        ),
      );
      final messages = (jsonDecode(sent.single.body)['messages'] as List)
          .cast<Map>();
      expect(messages.map((m) => m['role']), [
        'system',
        'user',
        'assistant',
        'user',
      ]);
      expect(messages[1]['content'], 'it is too small, like [id] said');
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
      expect(outcome.source.kind, AssistBackendKind.remote);
      expect(outcome.source.provider, 'groq');
      expect(outcome.timing!.inputTokens, 1400);
      expect(outcome.timing!.backend, 'remote');
    });

    test('rejects a call to a tool that was not offered', () async {
      final b = backend((_) => _json(200, _toolAnswer('delete_all_chats', {})));
      final outcome = await b.ask(AssistRequest('x', settings));
      expect(outcome.result, isA<AssistNoSuggestion>());
    });

    test('turns a text answer into a message', () async {
      final b = backend(
        (_) => _json(200, {
          'message': {
            'role': 'assistant',
            'content': '**Which** part is too small?',
          },
        }),
      );
      final outcome = await b.ask(AssistRequest('too small', settings));
      expect(
        (outcome.result as AssistMessage).text,
        'Which part is too small?',
      );
    });

    test('an empty answer is no suggestion', () async {
      final b = backend(
        (_) => _json(200, {
          'message': {'role': 'assistant', 'content': '  '},
        }),
      );
      expect(
        (await b.ask(AssistRequest('x', settings))).result,
        isA<AssistNoSuggestion>(),
      );
    });
  });

  group('errors', () {
    Future<AssistBackendUnavailable> failure(RemoteAssistBackend b) async {
      try {
        await b.ask(AssistRequest('x', settings));
      } on AssistBackendUnavailable catch (e) {
        return e;
      }
      fail('expected AssistBackendUnavailable');
    }

    test('ASSIST_FALLBACK', () async {
      final e = await failure(
        backend(
          (_) => _json(503, {
            'error': {'code': 'ASSIST_FALLBACK'},
          }),
        ),
      );
      expect(e.reason, 'fallback');
      expect(e.network, isFalse);
    });

    test('rate limited', () async {
      final e = await failure(
        backend(
          (_) => _json(429, {
            'error': {'code': 'ASSIST_RATE_LIMITED'},
          }),
        ),
      );
      expect(e.rateLimited, isTrue);
    });

    test('network error', () async {
      final e = await failure(
        backend((_) => throw const SocketException('down')),
      );
      expect(e.network, isTrue);
    });

    test('timeout', () async {
      final e = await failure(
        backend(
          (_) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 20),
        ),
      );
      expect(e.network, isTrue);
    });

    test('retries once with a new token after 401', () async {
      final b = backend(
        (request) => request.headers['authorization'] == 'Bearer openid-1'
            ? _json(401, {
                'error': {'code': 'ASSIST_UNAUTHORIZED'},
              })
            : _json(200, {
                'message': {'content': 'Hello'},
              }),
      );
      final outcome = await b.ask(AssistRequest('x', settings));
      expect(outcome.result, isA<AssistMessage>());
      expect(tokenRequests, 2);
      expect(sent, hasLength(2));
    });

    test('gives up after a second 401', () async {
      final e = await failure(
        backend(
          (_) => _json(401, {
            'error': {'code': 'ASSIST_UNAUTHORIZED'},
          }),
        ),
      );
      expect(e.reason, 'ASSIST_UNAUTHORIZED');
      expect(sent, hasLength(2));
    });

    test('a malformed body', () async {
      final e = await failure(backend((_) => http.Response('<html>', 200)));
      expect(e.reason, 'bad_response');
    });
  });

  group('OpenIdTokenSource', () {
    test('reuses a token until a minute before it expires', () async {
      var now = DateTime(2026, 11, 8, 12);
      var requests = 0;
      final source = OpenIdTokenSource(() async {
        requests++;
        return (token: 't$requests', expiresIn: const Duration(minutes: 60));
      }, now: () => now);
      expect(await source.get(), 't1');
      now = now.add(const Duration(minutes: 58));
      expect(await source.get(), 't1');
      now = now.add(const Duration(minutes: 2));
      expect(await source.get(), 't2');
      source.invalidate();
      expect(await source.get(), 't3');
    });
  });

  test('parseEndpoint accepts HTTPS and local development only', () {
    expect(
      RemoteAssistBackend.parseEndpoint(
        'https://matrix.example.org/_assist/v1/assist',
      ),
      isNotNull,
    );
    expect(
      RemoteAssistBackend.parseEndpoint('http://10.0.2.2:8080/v1/assist'),
      isNotNull,
    );
    expect(
      RemoteAssistBackend.parseEndpoint('http://matrix.example.org/x'),
      isNull,
    );
    expect(RemoteAssistBackend.parseEndpoint(''), isNull);
    expect(RemoteAssistBackend.parseEndpoint('not a url'), isNull);
  });
}
