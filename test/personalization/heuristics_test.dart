// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/heuristics/heuristics_engine.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);

  InteractionSignal signal(
    SignalType type, {
    TargetKind kind = TargetKind.button,
    Duration ago = Duration.zero,
  }) => InteractionSignal(type, now.subtract(ago), kind: kind);

  Heuristic heuristic(
    HeuristicCondition condition, {
    ScaleCategory category = ScaleCategory.button,
  }) => Heuristic(
    id: 'test',
    source: '',
    condition: condition,
    category: category,
    steps: 1,
    cooldown: const Duration(minutes: 30),
    descriptions: const {'en': 'English', 'da': 'Dansk'},
  );

  group('the bundled heuristics file', () {
    final json =
        jsonDecode(
              File(PersonalizationLayer.heuristicsAsset).readAsStringSync(),
            )
            as Map<String, Object?>;

    test('parses without errors', () {
      final errors = <Object>[];
      final config = HeuristicsConfig.fromJson(json, onError: errors.add);
      expect(errors, isEmpty);
      expect(config.heuristics.map((h) => h.id), [
        'near-miss-buttons',
        'text-zoom',
      ]);
    });

    test('every heuristic has English and Danish text', () {
      final config = HeuristicsConfig.fromJson(json);
      for (final h in config.heuristics) {
        expect(h.descriptions['en'], isNotEmpty, reason: h.id);
        expect(h.descriptions['da'], isNotEmpty, reason: h.id);
      }
    });

    test('is still marked as placeholder data', () {
      // Fails on purpose once the team replaces the values, as a reminder to
      // remove the flag and update this test.
      expect(json['placeholder'], isTrue);
    });
  });

  group('HeuristicsConfig.fromJson', () {
    test('skips broken heuristics and keeps the rest', () {
      final errors = <Object>[];
      final config = HeuristicsConfig.fromJson({
        'heuristics': [
          {
            'id': 'bad',
            'condition': {'type': 'count'},
            'change': {'category': 'button'},
            'description': {'en': 'x'},
          },
          {
            'id': 'unknown-category',
            'condition': {
              'type': 'count',
              'signal': 'pinch',
              'minCount': 1,
              'withinMinutes': 1,
            },
            'change': {'category': 'colour'},
            'description': {'en': 'x'},
          },
          {
            'id': 'good',
            'condition': {
              'type': 'count',
              'signal': 'pinch',
              'minCount': 1,
              'withinMinutes': 1,
            },
            'change': {'category': 'text', 'steps': 2},
            'description': {'en': 'x'},
          },
        ],
      }, onError: errors.add);
      expect(errors.length, 2);
      expect(config.heuristics.single.id, 'good');
      expect(config.heuristics.single.category, ScaleCategory.text);
      expect(config.heuristics.single.steps, 2);
    });

    test('description falls back to English', () {
      final h = heuristic(
        const CountCondition(
          signal: SignalType.pinch,
          targetKind: null,
          minCount: 1,
          within: Duration(minutes: 1),
        ),
      );
      expect(h.description('da'), 'Dansk');
      expect(h.description('de'), 'English');
    });
  });

  group('ShareCondition', () {
    const condition = ShareCondition(
      signal: SignalType.nearMiss,
      of: {SignalType.hit, SignalType.nearMiss},
      targetKind: TargetKind.button,
      minShare: 0.25,
      minEvents: 8,
    );

    test('needs enough events', () {
      final signals = [
        for (var i = 0; i < 3; i++) signal(SignalType.nearMiss),
        for (var i = 0; i < 4; i++) signal(SignalType.hit),
      ];
      expect(condition.isMetBy(signals, now), isFalse);
    });

    test('fires at the share threshold', () {
      final signals = [
        for (var i = 0; i < 2; i++) signal(SignalType.nearMiss),
        for (var i = 0; i < 6; i++) signal(SignalType.hit),
      ];
      expect(condition.isMetBy(signals, now), isTrue);
    });

    test('stays quiet below the share threshold', () {
      final signals = [
        signal(SignalType.nearMiss),
        for (var i = 0; i < 9; i++) signal(SignalType.hit),
      ];
      expect(condition.isMetBy(signals, now), isFalse);
    });

    test('ignores other target kinds', () {
      final signals = [
        for (var i = 0; i < 8; i++)
          signal(SignalType.nearMiss, kind: TargetKind.listItem),
      ];
      expect(condition.isMetBy(signals, now), isFalse);
    });
  });

  group('CountCondition', () {
    const condition = CountCondition(
      signal: SignalType.pinch,
      targetKind: TargetKind.text,
      minCount: 3,
      within: Duration(minutes: 5),
    );

    test('counts only recent matching signals', () {
      final signals = [
        signal(SignalType.pinch, kind: TargetKind.text),
        signal(
          SignalType.pinch,
          kind: TargetKind.text,
          ago: const Duration(minutes: 2),
        ),
        signal(
          SignalType.pinch,
          kind: TargetKind.text,
          ago: const Duration(minutes: 9),
        ),
      ];
      expect(condition.isMetBy(signals, now), isFalse);
      expect(
        condition.isMetBy([
          ...signals,
          signal(SignalType.pinch, kind: TargetKind.text),
        ], now),
        isTrue,
      );
    });
  });

  group('HeuristicsEngine', () {
    final alwaysTrue = heuristic(
      const CountCondition(
        signal: SignalType.hit,
        targetKind: null,
        minCount: 0,
        within: Duration(minutes: 1),
      ),
    );

    test('suggests one step up from the current value', () {
      final suggestion = HeuristicsEngine([
        alwaysTrue,
      ]).evaluate(const [], AccessibilitySettings.defaults, now).single;
      expect(suggestion.category, ScaleCategory.button);
      expect(suggestion.from, 1.0);
      expect(suggestion.to, 1.1);
    });

    test('suggests nothing when the category is already at its max', () {
      final settings = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.button,
        ScaleCategory.button.max,
      );
      expect(
        HeuristicsEngine([alwaysTrue]).evaluate(const [], settings, now),
        isEmpty,
      );
    });
  });
}
