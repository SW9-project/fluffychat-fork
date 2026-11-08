// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_prompt.dart';
import 'package:fluffychat/personalization/assist/assist_tools.dart';
import 'package:fluffychat/personalization/settings_registry.dart';
import 'package:flutter_test/flutter_test.dart';

AssistPromptTemplate shipped() => AssistPromptTemplate.parse(
  File(AssistPromptTemplate.assetPath).readAsStringSync(),
);

void main() {
  group('AssistPromptTemplate.parse', () {
    const markdown = '''
<!-- a note for the team
# System
that must not be sent -->
# System

You help.
- Be short.

# Heuristics

## target-size
- near-miss-buttons: Make buttons bigger.
not a heuristic line
- bad id!: ignored

## readability
<!-- PLACEHOLDER -->
- text-zoom: Make text bigger.
''';

    test('reads the system prompt without comments', () {
      final template = AssistPromptTemplate.parse(markdown);
      expect(template.system, 'You help.\n- Be short.');
    });

    test('reads heuristics per category and ignores other lines', () {
      final template = AssistPromptTemplate.parse(markdown);
      expect(template.categories.keys, ['target-size', 'readability']);
      expect(template.categories['target-size']!.map((r) => r.id), [
        'near-miss-buttons',
      ]);
      expect(template.ruleById('text-zoom')!.text, 'Make text bigger.');
      expect(template.ruleById('bad'), isNull);
    });
  });

  group('shipped heuristics.md', () {
    test('has a system prompt and every registry category', () {
      final template = shipped();
      expect(template.system, contains('older adults'));
      expect(template.system, contains('one short question'));
      for (final setting in SettingsRegistry.all) {
        expect(
          template.rulesIn(setting.heuristicCategories),
          isNotEmpty,
          reason: '${setting.id} needs at least one heuristic',
        );
      }
    });

    test('reuses the ids of the existing heuristics', () {
      final ids =
          (jsonDecode(
                    File(
                      'assets/personalization_heuristics.json',
                    ).readAsStringSync(),
                  )['heuristics']
                  as List)
              .map((h) => h['id']);
      final template = shipped();
      for (final id in ids) {
        expect(template.ruleById(id as String), isNotNull, reason: id);
      }
    });
  });

  group('AssistTools', () {
    test('offers one tool per registered setting', () {
      final tools = AssistTools.build(shipped());
      expect(
        tools.map((t) => t.name),
        SettingsRegistry.all.map((s) => 'set_${s.id}'),
      );
    });

    test('schemas match the registry and require heuristic and rationale', () {
      for (final tool in AssistTools.build(shipped())) {
        final setting = tool.setting as NumberSetting;
        final function = tool.toJson()['function'] as Map<String, Object?>;
        final parameters = function['parameters'] as Map<String, Object?>;
        final properties = parameters['properties'] as Map<String, Object?>;
        final value = properties['value'] as Map<String, Object?>;
        expect(value['minimum'], setting.min);
        expect(value['maximum'], setting.max);
        expect(parameters['required'], ['value', 'heuristic', 'rationale']);
        final heuristic = properties['heuristic'] as Map<String, Object?>;
        expect(heuristic['enum'], isNotEmpty);
        expect(heuristic['enum'], tool.heuristicIds);
        expect(function['name'], matches(RegExp(r'^[A-Za-z0-9_-]{1,64}$')));
      }
    });

    test('leaves out a setting whose categories have no heuristic', () {
      final template = AssistPromptTemplate.parse('''
# System
x
# Heuristics
## readability
- text-zoom: Make text bigger.
''');
      expect(AssistTools.build(template).map((t) => t.name), [
        'set_text_scale',
      ]);
    });

    test('tool heuristics come only from the setting\'s categories', () {
      final tools = AssistTools.build(shipped());
      final avatar = AssistTools.byName(tools, 'set_avatar_scale')!;
      expect(avatar.heuristicIds, contains('small-avatars'));
      expect(avatar.heuristicIds, isNot(contains('near-miss-buttons')));
    });
  });

  group('AssistPromptBuilder', () {
    test('includes current settings and the offered heuristics', () {
      final prompt = AssistPromptBuilder.build(
        shipped(),
        AccessibilitySettings.defaults.copyWith(ScaleCategory.button, 1.3),
      );
      expect(prompt.system, contains('- button_scale: 1.3'));
      expect(prompt.system, contains('- text_scale: 1.0'));
      expect(prompt.system, contains('near-miss-buttons'));
      expect(prompt.tools, hasLength(SettingsRegistry.all.length));
    });

    test('includes only categories relevant to the tools offered', () {
      final prompt = AssistPromptBuilder.build(
        shipped(),
        AccessibilitySettings.defaults,
        settingIds: ['avatar_scale'],
      );
      expect(prompt.tools.map((t) => t.name), ['set_avatar_scale']);
      expect(prompt.system, contains('small-avatars'));
      expect(prompt.system, isNot(contains('near-miss-buttons')));
      expect(prompt.system, isNot(contains('text_scale')));
    });

    test('the full request stays under the token budget', () {
      final prompt = AssistPromptBuilder.build(
        shipped(),
        AccessibilitySettings.defaults,
      );
      final request = jsonEncode({
        'messages': [
          {'role': 'system', 'content': prompt.system},
          {'role': 'user', 'content': 'The letters are much too small for me'},
        ],
        'tools': [for (final t in prompt.tools) t.toJson()],
      });
      final tokens = AssistPrompt.estimateTokens(request);
      expect(tokens, lessThan(AssistPromptBuilder.tokenBudget));
      // Printed so the team sees how much room is left.
      // ignore: avoid_print
      print('Estimated request size: $tokens tokens');
    });
  });
}
