// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_conversation.dart';
import 'package:fluffychat/personalization/model/app_change.dart';
import 'package:fluffychat/personalization/model/personalization_tools.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/model/tool_call_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Colors, ThemeMode;

final _tools = PersonalizationTools.fromJson(
  jsonDecode(File(PersonalizationTools.asset).readAsStringSync())
      as Map<String, Object?>,
);

AssistResult _interpret(
  String name,
  Map<String, Object?> args, {
  AccessibilitySettings settings = AccessibilitySettings.defaults,
  ThemeMode theme = ThemeMode.system,
  String? roomId,
}) => ToolCallInterpreter(
  tools: _tools,
  settings: settings,
  theme: theme,
).interpret(ProposedCall(name, args), roomId: roomId);

/// The settings a proposal would produce.
AccessibilitySettings _to(AssistResult result) =>
    (result as AssistProposal).change.to;

ScaleCategory _textTarget(String t) => switch (t) {
  'titles' => ScaleCategory.titleText,
  _ => ScaleCategory.text,
};

void main() {
  group('sizes', () {
    test('text: all text by default, one step by default', () {
      final to = _to(_interpret('change_text_size', {'direction': 'bigger'}));
      expect(to.textScale, 1.2);
      expect(to.messageTextScale, 1.0);
    });

    test('text: each target has its own size', () {
      for (final (target, category) in [
        ('messages', ScaleCategory.messageText),
        ('chat_list', ScaleCategory.chatListText),
        ('titles', ScaleCategory.titleText),
        ('message_input', ScaleCategory.inputText),
      ]) {
        final to = _to(
          _interpret('change_text_size', {
            'direction': 'smaller',
            'target': target,
            'steps': 2,
          }),
        );
        expect(to[category], 0.8, reason: target);
        expect(to.textScale, 1.0, reason: target);
      }
    });

    test('steps are clamped to 1 to 3 and accept numeric strings', () {
      expect(
        _to(
          _interpret('change_avatar_size', {'direction': 'bigger', 'steps': 9}),
        ).avatarScale,
        1.5,
      );
      expect(
        _to(
          _interpret('change_avatar_size', {
            'direction': 'bigger',
            'steps': '2',
          }),
        ).avatarScale,
        1.2,
      );
    });

    test('all buttons: icons and tap area; one button: only its own', () {
      final all = _to(
        _interpret('change_button_size', {'direction': 'bigger'}),
      );
      expect(all.buttonScale, 1.2);
      expect(all.touchTargetScale, 1.2);
      for (final button in AccessibleButton.values) {
        final one = _to(
          _interpret('change_button_size', {
            'direction': 'bigger',
            'button': button.name,
          }),
        );
        expect(one[button.category], 1.2, reason: button.name);
        expect(one.buttonScale, 1.0, reason: button.name);
      }
    });

    test('spacing: more and less', () {
      expect(
        _to(_interpret('change_spacing', {'direction': 'more'})).spacingScale,
        1.25,
      );
      expect(
        _to(
          _interpret('change_spacing', {'direction': 'less', 'steps': 3}),
        ).spacingScale,
        0.5,
      );
    });

    test('at the limit, nothing to propose', () {
      final settings = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.avatar,
        ScaleCategory.avatar.max,
      );
      final result = _interpret('change_avatar_size', {
        'direction': 'bigger',
      }, settings: settings);
      expect(result, isA<AssistUnchanged>());
      expect((result as AssistUnchanged).reason, UnchangedReason.atLimit);
      expect(result.category, ScaleCategory.avatar);
    });
  });

  group('sizes v2', () {
    test(
      'steps: 1 is one slider step, left out is the suggestion step, 3 is 0.5',
      () {
        double text(Map<String, Object?> a) => _to(
          _interpret('change_text_size', {'direction': 'bigger', ...a}),
        ).textScale;
        expect(text({'steps': 1}), 1.1);
        expect(text({}), 1.2);
        expect(text({'steps': 3}), 1.5);
        expect(
          _to(
            _interpret('change_spacing', {'direction': 'more', 'steps': 1}),
          ).spacingScale,
          1.25,
        );
      },
    );

    test(
      'size words: small is the minimum, medium 1.0, big 1.5, very_big 2.0',
      () {
        double text(String size, {String target = 'all'}) => _to(
          _interpret('change_text_size', {'size': size, 'target': target}),
        ).effective(_textTarget(target));
        expect(text('small'), 0.8);
        expect(
          _to(
            _interpret(
              'change_button_size',
              {'size': 'small'},
              settings: AccessibilitySettings.defaults.copyWith(
                ScaleCategory.button,
                1.5,
              ),
            ),
          ).buttonScale,
          1.0,
        );
        expect(text('very_big', target: 'titles'), 1.5);
        expect(text('big'), 1.5);
        expect(text('very_big'), 2.0);
        final from = AccessibilitySettings.defaults.copyWith(
          ScaleCategory.text,
          1.4,
        );
        expect(
          _to(
            _interpret('change_text_size', {'size': 'medium'}, settings: from),
          ).textScale,
          1.0,
        );
      },
    );

    test('size numbers as the model writes them', () {
      for (final (size, scale) in [
        ('1.6', 1.6),
        (' 1,6 ', 1.6),
        ('160%', 1.6),
        ('160 %', 1.6),
        ('Big', 1.5),
      ]) {
        expect(
          _to(_interpret('change_text_size', {'size': size})).textScale,
          scale,
          reason: size,
        );
      }
      for (final size in ['5', 'abc', '']) {
        final result = _interpret('change_text_size', {'size': size});
        expect(result, isA<AssistNoSuggestion>(), reason: size);
        expect(
          (result as AssistNoSuggestion).reason,
          RejectionReason.invalidArguments,
        );
      }
    });

    test('size wins over direction; neither is invalid', () {
      expect(
        _to(
          _interpret('change_text_size', {
            'size': 'big',
            'direction': 'smaller',
          }),
        ).textScale,
        1.5,
      );
      expect(_interpret('change_text_size', {}), isA<AssistNoSuggestion>());
    });

    test("one chat with a size sets that chat's whole message size", () {
      final interpreter = ToolCallInterpreter(
        tools: _tools,
        settings: AccessibilitySettings.defaults,
        theme: ThemeMode.system,
      );
      final to = _to(
        interpreter.forChat(
          const ProposedCall('change_text_size', {
            'size': 'big',
            'scope': 'one_chat',
          }),
          '!a',
        ),
      );
      expect(to.messageScale('!a'), 1.5);
    });

    test('an exact size that is already set says so, not at the limit', () {
      final interpreter = ToolCallInterpreter(
        tools: _tools,
        settings: AccessibilitySettings.defaults,
        theme: ThemeMode.system,
      );
      const medium = ProposedCall('change_text_size', {'size': 'medium'});
      for (final result in [
        interpreter.interpret(medium),
        interpreter.forChat(medium, '!a'),
      ]) {
        expect((result as AssistUnchanged).reason, UnchangedReason.alreadySet);
      }
    });
  });

  group('new functions', () {
    test('line spacing and read aloud use the settings', () {
      expect(
        _to(
          _interpret('change_line_spacing', {'direction': 'more'}),
        )[ScaleCategory.lineSpacing],
        1.2,
      );
      final less = _interpret('change_line_spacing', {'direction': 'less'});
      expect((less as AssistUnchanged).reason, UnchangedReason.atLimit);
      expect(
        _to(_interpret('set_read_aloud', {'enabled': true})).tripleTapToRead,
        isTrue,
      );
      final both = AccessibilitySettings.defaults
          .copyWith(ScaleCategory.lineSpacing, 1.5)
          .withToggle(AccessibilityToggle.tripleTapToRead, true)
          .copyWith(ScaleCategory.spacing, 1.5);
      final line = _to(
        _interpret('reset_settings', {
          'setting': 'line_spacing',
        }, settings: both),
      );
      expect(line[ScaleCategory.lineSpacing], 1.0);
      expect(line.tripleTapToRead, isTrue);
      expect(line.spacingScale, 1.5);
      final read = _to(
        _interpret('reset_settings', {'setting': 'read_aloud'}, settings: both),
      );
      expect(read.tripleTapToRead, isFalse);
      expect(read[ScaleCategory.lineSpacing], 1.5);
    });

    test('chat functions ask which chat first', () {
      const bubble = {'color': 'red', 'side': 'mine', 'scope': 'one_chat'};
      expect(_interpret('pin_chat', {'enabled': true}), isA<AssistNeedsChat>());
      expect(_interpret('set_bubble_color', bubble), isA<AssistNeedsChat>());
      expect(
        (_interpret('pin_chat', {'enabled': true}, roomId: '!a')
                as AssistAppProposal)
            .change,
        const AppChange(AppSetting.pinned, '!a', true),
      );
      expect(
        (_interpret('set_bubble_color', bubble, roomId: '!a')
                as AssistAppProposal)
            .change,
        AppChange(AppSetting.ownBubbleColor, '!a', Colors.red.toARGB32()),
      );
    });

    test('bubble color asks side, then color', () {
      var r = _interpret('set_bubble_color', {'color': 'red'});
      expect((r as AssistNeedsDetail).parameter, 'side');
      expect(r.options, ['mine', 'theirs']);
      r = _interpret('set_bubble_color', {'side': 'theirs'});
      expect((r as AssistNeedsDetail).parameter, 'color');
      expect(r.options, isNot(contains('default')));
      expect(r.options, contains('red'));
      expect(
        _interpret('set_bubble_color', {'side': 'mine', 'color': 'blue'}),
        isA<AssistAppProposal>(),
      );
    });

    test('withArg answers a question of the app', () {
      const call = ProposedCall('set_bubble_color', {'color': 'red'});
      expect(
        (_interpret(call.name, call.args) as AssistNeedsDetail).parameter,
        'side',
      );
      final answered = call.withArg('side', 'theirs');
      expect(
        (_interpret(answered.name, answered.args) as AssistAppProposal).change,
        AppChange(AppSetting.otherBubbleColor, null, Colors.red.toARGB32()),
      );
      expect(call.args, {'color': 'red'});
    });

    test('app color, wallpaper and gestures', () {
      AppChange change(AssistResult r) => (r as AssistAppProposal).change;
      expect(
        change(_interpret('set_app_color', {'color': 'default'})),
        AppChange(AppSetting.appColor, null, AppConfig.chatColor.toARGB32()),
      );
      expect(
        (_interpret('set_app_color', {}) as AssistNeedsDetail).parameter,
        'color',
      );
      expect(
        change(_interpret('set_wallpaper', {'wallpaper': 'blank'})),
        const AppChange(AppSetting.wallpaper, null, 'none'),
      );
      expect(
        change(_interpret('set_wallpaper', {'wallpaper': 'default'})).value,
        'none',
      );
      expect(
        change(
          _interpret('set_wallpaper', {
            'wallpaper': 'default',
            'scope': 'one_chat',
          }, roomId: '!a'),
        ),
        const AppChange(AppSetting.wallpaper, '!a', null),
      );
      expect(
        _interpret('set_wallpaper', {
          'wallpaper': 'pattern',
          'scope': 'one_chat',
        }),
        isA<AssistNeedsChat>(),
      );
      expect(
        change(
          _interpret('set_gesture', {
            'gesture': 'autoplay_gifs',
            'enabled': false,
          }),
        ),
        const AppChange(AppSetting.autoplayGifs, null, false),
      );
      expect(
        _interpret('set_gesture', {'gesture': 'shake', 'enabled': true}),
        isA<AssistNoSuggestion>(),
      );
    });

    test('mute false is unmute', () {
      expect(
        (_interpret('mute_chat', {'enabled': false}, roomId: '!a')
                as AssistAppProposal)
            .change,
        const AppChange(AppSetting.muted, '!a', false),
      );
    });
  });

  group('one chat', () {
    test('one_chat and a named chat ask which chat on the phone', () {
      for (final args in [
        {'direction': 'bigger', 'scope': 'one_chat'},
        {'direction': 'bigger', 'chat': 'Maria'},
        {'direction': 'bigger', 'scope': 'one_chat', 'chat': 'Maria'},
      ]) {
        expect(
          _interpret('change_text_size', args),
          isA<AssistNeedsChat>(),
          reason: '$args',
        );
      }
      final named =
          _interpret('change_text_size', {
                'direction': 'bigger',
                'chat': ' Maria ',
              })
              as AssistNeedsChat;
      expect(named.chatName, 'Maria');
    });

    test('forChat changes only that chat', () {
      const call = ProposedCall('change_text_size', {
        'direction': 'bigger',
        'scope': 'one_chat',
        'steps': 3,
      });
      final interpreter = ToolCallInterpreter(
        tools: _tools,
        settings: AccessibilitySettings.defaults,
        theme: ThemeMode.system,
      );
      final to = _to(interpreter.forChat(call, '!room'));
      expect(to.chatTextScale('!room'), 1.5);
      expect(to.chatTextScale('!other'), 1.0);
      expect(to.textScale, 1.0);
    });
  });

  group('switches and theme', () {
    test('labels and contrast turn on and off', () {
      expect(
        _to(_interpret('set_button_labels', {'enabled': true})).buttonLabels,
        isTrue,
      );
      final on = AccessibilitySettings.defaults.withToggle(
        AccessibilityToggle.highContrast,
        true,
      );
      expect(
        _to(
          _interpret('set_high_contrast', {'enabled': false}, settings: on),
        ).highContrast,
        isFalse,
      );
      expect(
        _interpret('set_high_contrast', {'enabled': true}, settings: on),
        isA<AssistUnchanged>(),
      );
    });

    test('theme changes only the theme', () {
      final result =
          _interpret('set_theme', {'mode': 'dark'}) as AssistProposal;
      expect(result.change.themeFrom, ThemeMode.system);
      expect(result.change.themeTo, ThemeMode.dark);
      expect(result.change.to, AccessibilitySettings.defaults);
      expect(
        _interpret('set_theme', {'mode': 'dark'}, theme: ThemeMode.dark),
        isA<AssistUnchanged>(),
      );
    });

    test('simple mode is not available yet', () {
      expect(
        _interpret('set_simple_mode', {'enabled': true}),
        isA<AssistNotAvailable>(),
      );
      expect(
        _interpret('reset_settings', {'setting': 'simple_mode'}),
        isA<AssistNotAvailable>(),
      );
    });
  });

  group('reset', () {
    final changed = AccessibilitySettings.defaults
        .copyWith(ScaleCategory.text, 1.5)
        .copyWith(ScaleCategory.chatListText, 1.2)
        .copyWith(ScaleCategory.button, 1.4)
        .copyWith(ScaleCategory.sendButton, 1.3)
        .copyWith(ScaleCategory.touchTarget, 1.2)
        .copyWith(ScaleCategory.spacing, 1.5)
        .copyWith(ScaleCategory.avatar, 1.6)
        .withToggle(AccessibilityToggle.buttonLabels, true)
        .withToggle(AccessibilityToggle.highContrast, true)
        .withChatText('!room', 1.4);

    test('all: everything back to normal', () {
      expect(
        _to(_interpret('reset_settings', {}, settings: changed)),
        AccessibilitySettings.defaults,
      );
    });

    test('one setting: only that one', () {
      final text = _to(
        _interpret('reset_settings', {
          'setting': 'text_size',
        }, settings: changed),
      );
      expect(text.textScale, 1.0);
      expect(text.chatListTextScale, 1.0);
      expect(text.chatTextScale('!room'), 1.0);
      expect(text.buttonScale, 1.4);

      final buttons = _to(
        _interpret('reset_settings', {
          'setting': 'button_size',
        }, settings: changed),
      );
      expect(buttons.buttonScale, 1.0);
      expect(buttons[ScaleCategory.sendButton], 1.0);
      expect(buttons.touchTargetScale, 1.0);
      expect(buttons.textScale, 1.5);

      for (final (setting, check) in [
        ('spacing', (AccessibilitySettings s) => s.spacingScale == 1.0),
        ('avatar_size', (AccessibilitySettings s) => s.avatarScale == 1.0),
        ('button_labels', (AccessibilitySettings s) => !s.buttonLabels),
        ('high_contrast', (AccessibilitySettings s) => !s.highContrast),
      ]) {
        final to = _to(
          _interpret('reset_settings', {'setting': setting}, settings: changed),
        );
        expect(check(to), isTrue, reason: setting);
        expect(to.textScale, 1.5, reason: setting);
      }
    });

    test('nothing to reset says so', () {
      expect(_interpret('reset_settings', {}), isA<AssistUnchanged>());
    });
  });

  group('clarification and no action', () {
    test('options keep declaration order and drop unknown names', () {
      final result =
          _interpret('ask_clarification', {
                'options': [
                  'change_avatar_size',
                  'delete_chat',
                  'change_text_size',
                ],
              })
              as AssistClarification;
      expect(result.options, ['change_text_size', 'change_avatar_size']);
    });

    test('no usable option is invalid', () {
      expect(
        _interpret('ask_clarification', {
          'options': ['delete_chat'],
        }),
        isA<AssistNoSuggestion>(),
      );
    });

    test('no_action', () {
      expect(_interpret('no_action', {}), isA<AssistNoAction>());
    });
  });

  group('rejected, never guessed', () {
    for (final (label, name, args) in [
      ('unknown function', 'set_text__button', <String, Object?>{}),
      ('missing direction', 'change_text_size', <String, Object?>{}),
      (
        'direction of another function',
        'change_spacing',
        {'direction': 'bigger'},
      ),
      (
        'unknown target',
        'change_text_size',
        {'direction': 'bigger', 'target': 'font'},
      ),
      (
        'unknown button',
        'change_button_size',
        {'direction': 'bigger', 'button': ' magnifying'},
      ),
      (
        'steps not a number',
        'change_text_size',
        {'direction': 'bigger', 'steps': 'lots'},
      ),
      ('enabled not a bool', 'set_button_labels', {'enabled': 'yes'}),
      ('unknown theme', 'set_theme', {'mode': 'blue'}),
      (
        'options not a list',
        'ask_clarification',
        {'options': 'change_text_size'},
      ),
    ]) {
      test(label, () {
        final result = _interpret(name, args);
        expect(result, isA<AssistNoSuggestion>(), reason: '$result');
      });
    }

    test('no call', () {
      final result = ToolCallInterpreter(
        tools: _tools,
        settings: AccessibilitySettings.defaults,
        theme: ThemeMode.system,
      ).interpret(null);
      expect((result as AssistNoSuggestion).reason, RejectionReason.noCall);
    });
  });

  group('AssistConversation', () {
    Object shape(ModelTurn turn) => switch (turn) {
      UserTurn(:final text) => ['user', text],
      CallTurn(:final call) => ['call', call.name, call.args],
      ResponseTurn(:final name, :final response) => [
        'response',
        name,
        response,
      ],
      ReplyTurn(:final text) => ['reply', text],
    };

    test('answer: the choice continues the same turn', () {
      final c = AssistConversation();
      c.ask('make it bigger');
      c.called(
        const ProposedCall('ask_clarification', {
          'options': ['change_text_size'],
        }),
      );
      expect(c.awaitsAnswer, isTrue);
      expect(c.answer('the text').map(shape), [
        ['user', 'make it bigger'],
        [
          'call',
          'ask_clarification',
          {
            'options': ['change_text_size'],
          },
        ],
        [
          'response',
          'ask_clarification',
          {'answer': 'the text'},
        ],
      ]);
    });

    test('adjust: one earlier exchange, ending in Done.', () {
      final c = AssistConversation();
      c.ask('make the text bigger');
      c.called(const ProposedCall('change_text_size', {'direction': 'bigger'}));
      c.resolved(applied: true);
      // Only the last answered exchange is kept.
      c.ask('a bit more');
      c.called(const ProposedCall('change_text_size', {'direction': 'bigger'}));
      c.resolved(applied: true);
      expect(c.ask('too much').map(shape), [
        ['user', 'a bit more'],
        [
          'call',
          'change_text_size',
          {'direction': 'bigger'},
        ],
        [
          'response',
          'change_text_size',
          {'status': 'applied'},
        ],
        ['reply', 'Done.'],
        ['user', 'too much'],
      ]);
    });

    test('correct: a decline or an undo', () {
      final c = AssistConversation();
      c.ask('the buttons are hard to hit');
      c.called(
        const ProposedCall('change_button_size', {'direction': 'bigger'}),
      );
      c.resolved(applied: true);
      c.undone();
      expect(c.ask('no, they are too close').map(shape).skip(2).take(2), [
        [
          'response',
          'change_button_size',
          {'status': 'declined'},
        ],
        ['reply', 'Okay, nothing changed.'],
      ]);
    });

    test('ended: the next request starts fresh', () {
      final c = AssistConversation();
      c.ask('make the text bigger');
      c.called(const ProposedCall('change_text_size', {'direction': 'bigger'}));
      c.resolved(applied: true);
      c.ask('what time is it');
      c.called(const ProposedCall('no_action', {}));
      c.ended();
      expect(c.ask('hello').map(shape), [
        ['user', 'hello'],
      ]);
    });
  });
}
