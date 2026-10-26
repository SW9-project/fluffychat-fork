// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences store;
  late AccessibilityController accessibility;
  late DateTime now;
  late SuggestionManager manager;

  Heuristic pinchHeuristic(String id, ScaleCategory category) => Heuristic(
    id: id,
    source: '',
    condition: const CountCondition(
      signal: SignalType.pinch,
      targetKind: TargetKind.text,
      minCount: 2,
      within: Duration(minutes: 5),
    ),
    category: category,
    steps: 1,
    cooldown: const Duration(minutes: 30),
    descriptions: {'en': id},
  );

  final config = HeuristicsConfig(
    signals: const SignalConfig(),
    undoDuration: const Duration(seconds: 10),
    heuristics: [
      pinchHeuristic('text-zoom', ScaleCategory.text),
      pinchHeuristic('avatar-zoom', ScaleCategory.avatar),
    ],
  );

  void pinch([int times = 2]) {
    for (var i = 0; i < times; i++) {
      manager.addSignal(
        InteractionSignal(SignalType.pinch, now, kind: TargetKind.text),
      );
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    accessibility = AccessibilityController(store);
    now = DateTime(2026, 1, 1, 12);
    manager = SuggestionManager(
      accessibility: accessibility,
      store: store,
      config: config,
      clock: () => now,
    );
  });

  test('no suggestion until a heuristic fires', () {
    pinch(1);
    expect(manager.current, isNull);
    pinch(1);
    expect(manager.current?.id, 'text-zoom');
  });

  test('nothing is applied without confirmation', () {
    pinch();
    expect(manager.current, isNotNull);
    expect(accessibility.settings, AccessibilitySettings.defaults);
  });

  test('only one suggestion is open at a time', () {
    pinch();
    final first = manager.current;
    pinch(4);
    expect(manager.current, same(first));
  });

  test('apply changes the setting and undo reverts it', () async {
    pinch();
    await manager.apply();
    expect(accessibility.settings.textScale, 1.1);
    expect(manager.current, isNull);
    expect(manager.applied?.suggestion.id, 'text-zoom');

    await manager.undoApplied();
    expect(accessibility.settings.textScale, 1.0);
    expect(manager.applied, isNull);
  });

  test('undo does not revert a later manual change', () async {
    pinch();
    await manager.apply();
    await accessibility.apply(ScaleCategory.avatar, 1.5);
    await manager.undoApplied();
    expect(accessibility.settings.textScale, 1.1);
    expect(accessibility.settings.avatarScale, 1.5);
  });

  test('the undo offer disappears after the undo period', () async {
    manager.config = HeuristicsConfig(
      signals: config.signals,
      undoDuration: const Duration(milliseconds: 100),
      heuristics: config.heuristics,
    );
    pinch();
    await manager.apply();
    expect(manager.applied, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(manager.applied, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(manager.applied, isNull);
  });

  test('after apply, continued problems suggest the next step', () async {
    pinch();
    await manager.apply();
    manager.dismissApplied();

    // The signals before applying were cleared, so new ones are needed.
    expect(manager.current, isNull);
    pinch();
    expect(manager.current?.id, 'text-zoom');
    expect(manager.current?.from, 1.1);
    expect(manager.current?.to, 1.2);
  });

  test('undo starts a cooldown like not now', () async {
    pinch();
    await manager.apply();
    await manager.undoApplied();
    pinch();
    expect(manager.current?.id, 'avatar-zoom');
  });

  test('no new suggestion while the undo offer is open', () async {
    pinch();
    await manager.apply();
    pinch();
    expect(manager.current, isNull);
  });

  test('not now starts a cooldown for that heuristic only', () {
    pinch();
    manager.notNow();
    expect(manager.current, isNull);

    // The cleared window needs new signals; the next heuristic may show.
    pinch();
    expect(manager.current?.id, 'avatar-zoom');
    manager.notNow();

    now = now.add(const Duration(minutes: 10));
    pinch();
    expect(manager.current, isNull);

    now = now.add(const Duration(minutes: 25));
    pinch();
    expect(manager.current?.id, 'text-zoom');
  });

  test('resolving a suggestion clears the signal window', () {
    pinch();
    manager.notNow();
    now = now.add(const Duration(hours: 1));
    pinch(1);
    expect(manager.current, isNull);
  });

  test('opt-out is permanent and stored', () async {
    pinch();
    await manager.optOut();
    expect(manager.optedOut, {'text-zoom'});
    expect(store.getStringList(SuggestionManager.optOutKey), ['text-zoom']);

    final restarted = SuggestionManager(
      accessibility: accessibility,
      store: store,
      config: config,
      clock: () => now.add(const Duration(days: 30)),
    );
    for (var i = 0; i < 2; i++) {
      restarted.addSignal(
        InteractionSignal(
          SignalType.pinch,
          now.add(const Duration(days: 30)),
          kind: TargetKind.text,
        ),
      );
    }
    expect(restarted.current?.id, 'avatar-zoom');
  });

  test('no suggestion when the category is already at its max', () async {
    await accessibility.apply(ScaleCategory.text, ScaleCategory.text.max);
    pinch();
    expect(manager.current?.id, 'avatar-zoom');
  });
}
