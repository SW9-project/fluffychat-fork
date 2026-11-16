// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/heuristic_functions.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/model/v2_settings_functions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final config = HeuristicsConfig.fromJson(
    jsonDecode(
          File('assets/personalization_heuristics.json').readAsStringSync(),
        )
        as Map<String, Object?>,
  );

  test('offers only the V2 tools for settings enabled in the app', () {
    expect(
      V2SettingsFunctions.declarationsFor(config.heuristics).map((f) => f.name),
      ['change_text_zoom', 'change_button'],
    );
    expect(V2SettingsFunctions.declarationsFor(const []), isEmpty);
  });

  test(
    'maps both text directions to bounded proposals with matching descriptions',
    () {
      for (final direction in ['bigger', 'smaller']) {
        final result = V2SettingsFunctions.interpret(
          ProposedCall('change_text_zoom', {'direction': direction}),
          config.heuristics,
          AccessibilitySettings.defaults,
        );
        expect(result, isA<AssistProposal>());
        final proposal = result as AssistProposal;
        expect(proposal.category, ScaleCategory.text);
        expect(proposal.from, 1);
        expect(proposal.to, direction == 'bigger' ? 1.1 : 0.9);
        expect(proposal.heuristic.description('en'), contains(direction));
      }
    },
  );

  test('preserves setting limits', () {
    expect(
      V2SettingsFunctions.interpret(
        const ProposedCall('change_button', {'direction': 'smaller'}),
        config.heuristics,
        AccessibilitySettings.defaults,
      ),
      isA<AssistAtLimit>(),
    );
    final max = AccessibilitySettings.defaults.copyWith(ScaleCategory.text, 2);
    expect(
      V2SettingsFunctions.interpret(
        const ProposedCall('change_text_zoom', {'direction': 'bigger'}),
        config.heuristics,
        max,
      ),
      isA<AssistAtLimit>(),
    );
  });

  test(
    'rejects unrelated directions, extra arguments, and unoffered functions',
    () {
      for (final call in [
        const ProposedCall('change_text_zoom', {'direction': 'high_contrast'}),
        const ProposedCall('change_button', {'direction': 'change_spacing'}),
        const ProposedCall('change_button', {'direction': true}),
        const ProposedCall('change_button', {
          'direction': 'bigger',
          'steps': 100,
        }),
        const ProposedCall('set_simple_text_button', {'direction': 'simple'}),
        const ProposedCall('heuristic_text_zoom', {}),
      ]) {
        expect(
          V2SettingsFunctions.interpret(
            call,
            config.heuristics,
            AccessibilitySettings.defaults,
          ),
          isA<AssistNoSuggestion>(),
        );
      }
      expect(
        V2SettingsFunctions.interpret(
          const ProposedCall('change_button', {'direction': 'bigger'}),
          const [],
          AccessibilitySettings.defaults,
        ),
        isA<AssistNoSuggestion>(),
      );
    },
  );
}
