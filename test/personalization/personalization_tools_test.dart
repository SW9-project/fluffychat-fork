// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/assist/assist_conversation.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/personalization_tools.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _file() =>
    jsonDecode(File(PersonalizationTools.asset).readAsStringSync())
        as Map<String, Object?>;

void main() {
  final tools = PersonalizationTools.fromJson(_file());

  group('the functions the model was trained on', () {
    test('are offered as in the file, in its order', () {
      final names = [
        for (final f in _file()['functions'] as List)
          (f as Map<String, Object?>)['name'],
      ];
      expect([for (final d in tools.declarations) d.name], names);
      expect(names, [
        ...PersonalizationTools.changeFunctions.take(3),
        PersonalizationTools.setSimpleMode,
        PersonalizationTools.setButtonLabels,
        PersonalizationTools.setHighContrast,
        PersonalizationTools.changeAvatarSize,
        PersonalizationTools.setTheme,
        PersonalizationTools.resetSettings,
        PersonalizationTools.askClarification,
        PersonalizationTools.noAction,
      ]);
    });

    test('keep their exact descriptions', () {
      for (final (i, f) in (_file()['functions'] as List).indexed) {
        final json = f as Map<String, Object?>;
        expect(tools.declarations[i].description, json['description']);
      }
    });

    test('reach the model without default, minimum and maximum', () {
      final sent = jsonEncode([
        for (final d in tools.declarations) d.parameters,
      ]);
      expect(sent, isNot(contains('"default"')));
      expect(sent, isNot(contains('"minimum"')));
      expect(sent, isNot(contains('"maximum"')));
      // Everything else is kept, such as the enum of a list's items.
      expect(sent, contains('"items"'));
    });

    test('reach the model with every key sorted, as the training prompts', () {
      void sorted(Object? value, String where) {
        if (value is Map) {
          final keys = value.keys.cast<String>().toList();
          expect(keys, [...keys]..sort(), reason: where);
          for (final MapEntry(:key, :value) in value.entries) {
            sorted(value, '$where.$key');
          }
        } else if (value is List) {
          for (final item in value) {
            sorted(item, where);
          }
        }
      }

      for (final d in tools.declarations) {
        sorted(d.parameters, d.name);
      }
      // The template leaves out what is empty.
      final noAction = tools.declarations.last;
      expect(noAction.parameters, {'type': 'object'});
      final reset = tools.declarations.firstWhere(
        (d) => d.name == 'reset_settings',
      );
      expect(reset.parameters.containsKey('required'), isFalse);
      // Enum values keep the file's order.
      final button = tools.declarations[1].parameters['properties'] as Map;
      expect((button['button'] as Map)['enum'], [
        'all',
        'send',
        'attach',
        'emoji',
        'microphone',
        'back',
        'search',
        'menu',
        'navigation',
      ]);
    });

    test('the app reads defaults and ranges from the file', () {
      expect(tools.defaultOf('change_text_size', 'target'), 'all');
      expect(tools.rangeOf('change_spacing', 'steps'), (1, 3));
      expect(tools.enumOf('change_button_size', 'button'), contains('menu'));
      expect(tools.requiredOf('set_theme'), ['mode']);
    });

    test('every function has training examples', () {
      final source = Directory('training/source');
      if (!source.existsSync()) return markTestSkipped('No training folder');
      for (final d in tools.declarations) {
        expect(
          File('training/source/${d.name}.json').existsSync(),
          isTrue,
          reason: d.name,
        );
      }
    });
  });

  group('turns as LiteRT-LM messages', () {
    test('a call\'s arguments are sorted, as the training template did', () {
      final message = FunctionGemmaModel.messageOf(
        const CallTurn(
          ProposedCall('change_button_size', {
            'direction': 'bigger',
            'button': 'back',
          }),
        ),
      );
      final function =
          ((message['tool_calls'] as List).single as Map)['function'] as Map;
      expect((function['arguments'] as Map).keys, ['button', 'direction']);
    });

    test('match the roles and shapes of the training conversations', () {
      const call = ProposedCall('change_text_size', {'direction': 'bigger'});
      expect(FunctionGemmaModel.messageOf(const UserTurn('make it bigger')), {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'make it bigger'},
        ],
      });
      expect(FunctionGemmaModel.messageOf(const CallTurn(call)), {
        'role': 'assistant',
        'tool_calls': [
          {
            'type': 'function',
            'function': {
              'name': 'change_text_size',
              'arguments': {'direction': 'bigger'},
            },
          },
        ],
      });
      expect(
        FunctionGemmaModel.messageOf(
          const ResponseTurn('change_text_size', {'status': 'applied'}),
        ),
        {
          'role': 'tool',
          'content': [
            {
              'type': 'tool_response',
              'name': 'change_text_size',
              'response': {'status': 'applied'},
            },
          ],
        },
      );
      expect(
        FunctionGemmaModel.messageOf(
          const ReplyTurn(AssistConversation.appliedReply),
        ),
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'Done.'},
          ],
        },
      );
    });
  });
}
