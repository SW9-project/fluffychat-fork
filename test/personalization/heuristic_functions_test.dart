// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/heuristic_functions.dart';
import 'package:fluffychat/personalization/model/settings_call_validator.dart';
import 'package:fluffychat/personalization/model/settings_functions.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:flutter_test/flutter_test.dart';

Heuristic heuristic({
  String id = 'test-rule',
  String? rule = 'When X is hard, make it bigger.',
  ScaleCategory category = ScaleCategory.button,
  int steps = 1,
}) => Heuristic(
  id: id,
  source: '',
  condition: const CountCondition(
    signal: SignalType.pinch,
    targetKind: null,
    minCount: 1,
    within: Duration(minutes: 1),
  ),
  category: category,
  steps: steps,
  cooldown: const Duration(minutes: 30),
  descriptions: const {'en': 'Premade text'},
  rule: rule,
);

void main() {
  group('from the bundled heuristics file', () {
    final config = HeuristicsConfig.fromJson(
      jsonDecode(File(PersonalizationLayer.heuristicsAsset).readAsStringSync())
          as Map<String, Object?>,
    );
    final functions = HeuristicFunctions.declarationsFor(config.heuristics);

    test('one function per heuristic, named after its id', () {
      expect(functions.map((f) => f.name), [
        'heuristic_near_miss_buttons',
        'heuristic_text_zoom',
      ]);
    });

    test('the description is the heuristic rule', () {
      for (final h in config.heuristics) {
        final f = functions.firstWhere(
          (f) => f.name == HeuristicFunctions.nameFor(h),
        );
        expect(f.description, h.rule);
        expect(f.description, isNotEmpty);
      }
    });

    test('the only parameter is steps, from 1 to the max', () {
      for (final f in functions) {
        final properties = f.parameters['properties'] as Map;
        expect(properties.keys, ['steps']);
        final steps = properties['steps'] as Map;
        expect(steps['minimum'], 1);
        expect(steps['maximum'], SettingsFunctions.maxSteps);
        expect(f.parameters['required'], isEmpty);
      }
    });

    test('the old adjust functions are not offered', () {
      expect(
        functions.map((f) => f.name),
        isNot(contains(startsWith('adjust_'))),
      );
    });
  });

  test('a heuristic without a rule is not offered', () {
    final functions = HeuristicFunctions.declarationsFor([
      heuristic(id: 'with-rule'),
      heuristic(id: 'without-rule', rule: null),
      heuristic(id: 'blank-rule', rule: '  '),
    ]);
    expect(functions.map((f) => f.name), ['heuristic_with_rule']);
  });

  group('interpret', () {
    const defaults = AccessibilitySettings.defaults;
    final buttons = heuristic(id: 'near-miss-buttons');
    final heuristics = [buttons];

    AssistResult interpret(
      ProposedCall? call, [
      AccessibilitySettings settings = defaults,
      List<Heuristic>? list,
    ]) => HeuristicFunctions.interpret(call, list ?? heuristics, settings);

    test('no call means no suggestion', () {
      final result = interpret(null) as AssistNoSuggestion;
      expect(result.reason, RejectionReason.noCall);
    });

    test('an unknown function means no suggestion', () {
      for (final name in ['heuristic_unknown', 'adjust_button_size', '']) {
        final result =
            interpret(ProposedCall(name, const {'direction': 'bigger'}))
                as AssistNoSuggestion;
        expect(result.reason, RejectionReason.unknownFunction, reason: name);
      }
    });

    test('category and direction come from the heuristic', () {
      final result =
          interpret(
                const ProposedCall('heuristic_near_miss_buttons', {
                  // The model cannot change these.
                  'direction': 'smaller',
                  'category': 'avatar',
                }),
              )
              as AssistProposal;
      expect(result.heuristic, same(buttons));
      expect(result.category, ScaleCategory.button);
      expect(result.from, 1.0);
      expect(result.to, 1.1);
    });

    test('steps from the model are used and clamped', () {
      expect(
        (interpret(
                  const ProposedCall('heuristic_near_miss_buttons', {
                    'steps': 2,
                  }),
                )
                as AssistProposal)
            .to,
        1.2,
      );
      expect(
        (interpret(
                  const ProposedCall('heuristic_near_miss_buttons', {
                    'steps': 99,
                  }),
                )
                as AssistProposal)
            .to,
        1.3,
      );
    });

    test('unusable steps mean no suggestion', () {
      final result =
          interpret(
                const ProposedCall('heuristic_near_miss_buttons', {
                  'steps': 'a lot',
                }),
              )
              as AssistNoSuggestion;
      expect(result.reason, RejectionReason.invalidArguments);
    });

    test('a heuristic that makes things smaller', () {
      final smaller = heuristic(
        id: 'too-big',
        category: ScaleCategory.avatar,
        steps: -1,
      );
      final settings = defaults.copyWith(ScaleCategory.avatar, 1.5);
      final result =
          interpret(const ProposedCall('heuristic_too_big', {}), settings, [
                smaller,
              ])
              as AssistProposal;
      expect(result.to, 1.4);
    });

    test('a heuristic with several steps multiplies the model steps', () {
      final big = heuristic(id: 'big', steps: 2);
      final result =
          interpret(
                const ProposedCall('heuristic_big', {'steps': 1}),
                defaults,
                [big],
              )
              as AssistProposal;
      expect(result.to, 1.2);
    });

    test('a setting at its limit is reported as such', () {
      final settings = defaults.copyWith(
        ScaleCategory.button,
        ScaleCategory.button.max,
      );
      final result =
          interpret(
                const ProposedCall('heuristic_near_miss_buttons', {}),
                settings,
              )
              as AssistAtLimit;
      expect(result.category, ScaleCategory.button);
    });
  });
}
