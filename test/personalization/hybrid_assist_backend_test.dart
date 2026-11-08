// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_backend.dart';
import 'package:fluffychat/personalization/assist/assist_result.dart';
import 'package:fluffychat/personalization/assist/hybrid_assist_backend.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend extends AssistBackend {
  final AssistBackendKind kind;
  final ValueNotifier<ModelStatus> _status;
  Object? failWith;
  int asks = 0;

  FakeBackend(this.kind, [ModelState state = ModelState.ready])
    : _status = ValueNotifier(ModelStatus(state));

  set state(ModelState state) => _status.value = ModelStatus(state);

  @override
  ValueListenable<ModelStatus> get status => _status;

  @override
  Future<void> prepare() async => state = ModelState.ready;

  @override
  Future<AssistOutcome> ask(AssistRequest request) async {
    asks++;
    if (failWith case final e?) throw e;
    return AssistOutcome(
      AssistMessage('from ${kind.name}'),
      AssistSource(
        kind,
        provider: kind == AssistBackendKind.remote ? 'groq' : null,
      ),
    );
  }

  @override
  void dispose() {}
}

void main() {
  const request = AssistRequest('hello', AccessibilitySettings.defaults);
  late FakeBackend remote;
  late FakeBackend local;
  late DateTime now;
  late HybridAssistBackend hybrid;

  setUp(() {
    remote = FakeBackend(AssistBackendKind.remote);
    local = FakeBackend(AssistBackendKind.local);
    now = DateTime(2026, 11, 8, 12);
    hybrid = HybridAssistBackend(remote: remote, local: local, now: () => now);
  });

  String text(AssistOutcome o) => (o.result as AssistMessage).text;

  test('uses the online assistant when it answers', () async {
    final outcome = await hybrid.ask(request);
    expect(text(outcome), 'from remote');
    expect(outcome.source.provider, 'groq');
    expect(local.asks, 0);
  });

  test('falls back to the on-device model on ASSIST_FALLBACK', () async {
    remote.failWith = const AssistBackendUnavailable('fallback');
    final outcome = await hybrid.ask(request);
    expect(text(outcome), 'from local');
    expect(outcome.source.kind, AssistBackendKind.local);
    expect(outcome.source.fallbackReason, 'fallback');
  });

  test('falls back when rate limited', () async {
    remote.failWith = const AssistBackendUnavailable(
      'rate_limited',
      rateLimited: true,
    );
    expect(text(await hybrid.ask(request)), 'from local');
  });

  test('says the assistant is unavailable when no fallback is ready', () async {
    local.state = ModelState.notPrepared;
    remote.failWith = const AssistBackendUnavailable('network', network: true);
    final outcome = await hybrid.ask(request);
    expect(
      outcome.result,
      isA<AssistUnavailable>().having(
        (r) => r.reason,
        'reason',
        AssistUnavailableReason.offline,
      ),
    );

    remote.failWith = const AssistBackendUnavailable(
      'rate_limited',
      rateLimited: true,
    );
    expect(
      (await hybrid.ask(request)).result,
      isA<AssistUnavailable>().having(
        (r) => r.reason,
        'reason',
        AssistUnavailableReason.rateLimited,
      ),
    );
  });

  test(
    'skips the online assistant for a minute after a network failure',
    () async {
      remote.failWith = const AssistBackendUnavailable(
        'network',
        network: true,
      );
      await hybrid.ask(request);
      expect(remote.asks, 1);

      now = now.add(const Duration(seconds: 30));
      final outcome = await hybrid.ask(request);
      expect(remote.asks, 1);
      expect(outcome.source.fallbackReason, 'offline');

      now = now.add(const Duration(seconds: 31));
      remote.failWith = null;
      expect(text(await hybrid.ask(request)), 'from remote');
      expect(remote.asks, 2);
    },
  );

  test(
    'still tries online during the cooldown when no fallback is ready',
    () async {
      local.state = ModelState.notPrepared;
      remote.failWith = const AssistBackendUnavailable(
        'network',
        network: true,
      );
      await hybrid.ask(request);
      await hybrid.ask(request);
      expect(remote.asks, 2);
    },
  );

  test('is ready with an online assistant and shows the offline state', () {
    local.state = ModelState.notPrepared;
    expect(hybrid.status.value.state, ModelState.ready);
    expect(hybrid.offlineStatus!.value.state, ModelState.notPrepared);
  });

  test('without an online assistant it is the on-device model', () async {
    final offline = HybridAssistBackend(local: local);
    expect(offline.offlineStatus, isNull);
    local.state = ModelState.notPrepared;
    expect(offline.status.value.state, ModelState.notPrepared);
    await offline.prepare();
    expect(offline.status.value.state, ModelState.ready);
    expect(text(await offline.ask(request)), 'from local');
  });

  test('with neither it is unavailable', () {
    expect(HybridAssistBackend().status.value.state, ModelState.unavailable);
  });
}
