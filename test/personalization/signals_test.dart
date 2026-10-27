// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  const send = TargetSnapshot(
    'send',
    TargetKind.button,
    Rect.fromLTWH(100, 100, 48, 48),
  );
  const row = TargetSnapshot(
    'row',
    TargetKind.listItem,
    Rect.fromLTWH(0, 80, 400, 88),
  );
  const timeline = TargetSnapshot(
    'timeline',
    TargetKind.text,
    Rect.fromLTWH(0, 0, 400, 800),
  );
  const card = TargetSnapshot(
    'card',
    TargetKind.excluded,
    Rect.fromLTWH(0, 0, 400, 60),
  );

  group('distanceToRect', () {
    const rect = Rect.fromLTWH(10, 10, 10, 10);
    test('is zero inside', () {
      expect(distanceToRect(const Offset(15, 15), rect), 0);
    });
    test('measures to the closest edge or corner', () {
      expect(distanceToRect(const Offset(25, 15), rect), 5);
      expect(distanceToRect(const Offset(23, 24), rect), 5);
    });
  });

  group('TapClassifier', () {
    test('a tap inside a button is a hit', () {
      final signals = TapClassifier(
        const SignalConfig(),
      ).classify(const Offset(120, 120), [send], t0);
      expect(signals.single.type, SignalType.hit);
      expect(signals.single.kind, TargetKind.button);
      expect(signals.single.targetId, 'send');
    });

    test('a tap just outside a button is a near miss', () {
      final signals = TapClassifier(
        const SignalConfig(nearMissDistance: 16),
      ).classify(const Offset(160, 120), [send], t0);
      expect(signals.single.type, SignalType.nearMiss);
      expect(signals.single.targetId, 'send');
    });

    test('a tap far from every target gives no signal', () {
      final signals = TapClassifier(
        const SignalConfig(nearMissDistance: 16),
      ).classify(const Offset(300, 300), [send], t0);
      expect(signals, isEmpty);
    });

    test('the smallest containing target wins', () {
      final signals = TapClassifier(
        const SignalConfig(),
      ).classify(const Offset(120, 120), [row, send], t0);
      expect(signals.single.targetId, 'send');
    });

    test('a tap inside a list item but near a button is a list item hit', () {
      final signals = TapClassifier(
        const SignalConfig(nearMissDistance: 16),
      ).classify(const Offset(160, 120), [row, send], t0);
      expect(signals.single.type, SignalType.hit);
      expect(signals.single.targetId, 'row');
    });

    test('text targets never count as hits or near misses', () {
      final signals = TapClassifier(
        const SignalConfig(),
      ).classify(const Offset(300, 300), [timeline], t0);
      expect(signals, isEmpty);
    });

    test('taps in excluded areas are ignored', () {
      final classifier = TapClassifier(const SignalConfig());
      final signals = classifier.classify(const Offset(110, 30), [
        card,
        const TargetSnapshot(
          'back',
          TargetKind.button,
          Rect.fromLTWH(100, 20, 48, 48),
        ),
      ], t0);
      expect(signals, isEmpty);
    });

    test('a second tap on the same spot soon after is a repeated tap', () {
      final classifier = TapClassifier(
        const SignalConfig(
          repeatedTapWindow: Duration(milliseconds: 600),
          repeatedTapDistance: 24,
        ),
      );
      classifier.classify(const Offset(120, 120), [send], t0);
      final signals = classifier.classify(const Offset(125, 122), [
        send,
      ], t0.add(const Duration(milliseconds: 400)));
      expect(signals.map((s) => s.type), [
        SignalType.hit,
        SignalType.repeatedTap,
      ]);

      final late = classifier.classify(const Offset(125, 122), [
        send,
      ], t0.add(const Duration(seconds: 2)));
      expect(late.map((s) => s.type), [SignalType.hit]);
    });
  });

  group('SignalWindow', () {
    test('drops signals older than the window', () {
      final window = SignalWindow(
        const SignalConfig(window: Duration(minutes: 10)),
      );
      window.add(InteractionSignal(SignalType.hit, t0));
      window.add(
        InteractionSignal(SignalType.hit, t0.add(const Duration(minutes: 8))),
      );
      expect(window.recent(t0.add(const Duration(minutes: 12))).length, 1);
    });

    test('keeps at most maxEvents signals', () {
      final window = SignalWindow(const SignalConfig(maxEvents: 3));
      for (var i = 0; i < 5; i++) {
        window.add(
          InteractionSignal(SignalType.hit, t0.add(Duration(seconds: i))),
        );
      }
      final recent = window.recent(t0.add(const Duration(seconds: 5)));
      expect(recent.length, 3);
      expect(recent.first.time, t0.add(const Duration(seconds: 2)));
    });
  });

  test('SignalConfig reads the JSON fields', () {
    final config = SignalConfig.fromJson({
      'nearMissDistance': 20,
      'repeatedTapWindowMs': 700,
      'repeatedTapDistance': 30,
      'pinchMinChange': 0.2,
      'windowMinutes': 5,
      'maxEvents': 100,
    });
    expect(config.nearMissDistance, 20);
    expect(config.repeatedTapWindow, const Duration(milliseconds: 700));
    expect(config.repeatedTapDistance, 30);
    expect(config.pinchMinChange, 0.2);
    expect(config.window, const Duration(minutes: 5));
    expect(config.maxEvents, 100);
  });
}
