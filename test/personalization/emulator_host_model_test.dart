// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/personalization/model/assistant_model_config.dart';
import 'package:fluffychat/personalization/model/emulator_host_model.dart';
import 'package:fluffychat/personalization/model/personalization_tools.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final readyHealth = jsonEncode({
    'ready': true,
    'model': AssistantModelConfig.id,
    'sha256': AssistantModelConfig.sha256,
  });
  const functions = [
    FunctionDeclaration(
      name: 'heuristic_text_zoom',
      description: 'Make hard-to-read text bigger.',
      parameters: {'type': 'object'},
    ),
  ];

  test('disabled in normal builds', () {
    expect(EmulatorHostModel.enabled, isFalse);
  });

  test('sends only the prompt and offered functions over loopback', () async {
    final requests = <http.Request>[];
    final model = EmulatorHostModel(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/health') {
          return http.Response(readyHealth, 200);
        }
        return http.Response(
          '{"call":{"name":"heuristic_text_zoom","args":{"steps":2}}}',
          200,
        );
      }),
    );
    addTearDown(model.dispose);
    final call = await model.propose(const [
      UserTurn('Text is tiny'),
    ], functions);
    expect(model.status.value.state, ModelState.ready);
    expect(call?.name, 'heuristic_text_zoom');
    expect(call?.args, {'steps': 2});
    expect(model.lastTiming?.backend, 'development-host-cpu');
    expect(requests.every((r) => r.url.host == '127.0.0.1'), isTrue);
    final body = jsonDecode(requests.last.body) as Map;
    expect(body.keys, unorderedEquals(['text', 'functions']));
    expect(body['text'], 'Text is tiny');
    expect((body['functions'] as List).single['name'], functions.single.name);
  });

  test('rejects the old model and a host with mismatched weights', () async {
    for (final health in [
      {
        'ready': true,
        'model': 'functiongemma-270M-sw9-pilot1',
        'sha256': AssistantModelConfig.sha256,
      },
      {'ready': true, 'model': AssistantModelConfig.id, 'sha256': 'wrong'},
      {'ready': true},
    ]) {
      final model = EmulatorHostModel(
        client: MockClient((_) async => http.Response(jsonEncode(health), 200)),
      );
      await model.prepare();
      expect(model.status.value.state, ModelState.failed);
      model.dispose();
    }
  });

  test('offline preparation fails and can be retried', () async {
    var online = false;
    final model = EmulatorHostModel(
      client: MockClient(
        (_) async =>
            online ? http.Response(readyHealth, 200) : http.Response('{}', 503),
      ),
    );
    addTearDown(model.dispose);
    await model.prepare();
    expect(model.status.value.state, ModelState.failed);
    online = true;
    await model.prepare();
    expect(model.status.value.state, ModelState.ready);
  });

  test('null proposal does not invent a change', () async {
    final model = EmulatorHostModel(
      client: MockClient(
        (request) async => http.Response(
          request.url.path == '/health' ? readyHealth : '{"call":null}',
          200,
        ),
      ),
    );
    addTearDown(model.dispose);
    expect(await model.propose(const [UserTurn('Hello')], functions), isNull);
  });

  test('malformed proposals and server errors are not accepted', () async {
    var malformed = true;
    final model = EmulatorHostModel(
      client: MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(readyHealth, 200);
        }
        return malformed
            ? http.Response('{"call":{"name":3,"args":[]}}', 200)
            : http.Response('{}', 500);
      }),
    );
    addTearDown(model.dispose);
    await expectLater(
      model.propose(const [UserTurn('Tiny')], functions),
      throwsFormatException,
    );
    malformed = false;
    await expectLater(
      model.propose(const [UserTurn('Tiny')], functions),
      throwsStateError,
    );
    expect(model.lastTiming, isNull);
  });
}
