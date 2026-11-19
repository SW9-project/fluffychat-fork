// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/app_change.dart';
import 'package:fluffychat/personalization/model/personalization_tools.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:fluffychat/personalization/voice/speech_transcriber.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_actions.dart';
import 'fake_transcriber.dart';

class MemoryStorage implements StudyLogStorage {
  final List<String> lines = [];

  @override
  Future<void> append(String line) async => lines.add(line);

  @override
  Future<List<String>> readLines() async => [...lines];

  @override
  Future<void> clear() async => lines.clear();
}

class FakeModel implements SettingsIntentModel {
  final ValueNotifier<ModelStatus> _status;

  /// The answer to the last turn of each request.
  ProposedCall? Function(ModelTurn last) answer;
  int prepareCalls = 0;
  final List<List<ModelTurn>> requests = [];
  final List<List<String>> offered = [];

  /// The user's words of each request.
  List<String> get prompts => [
    for (final request in requests)
      if (request.last case UserTurn(:final text)) text,
  ];

  @override
  ModelTiming? lastTiming;

  FakeModel(ModelState state, {ProposedCall? Function(ModelTurn)? answer})
    : _status = ValueNotifier(ModelStatus(state)),
      answer = answer ?? ((_) => null);

  /// The same call for every request.
  FakeModel.calls(ProposedCall call)
    : this(ModelState.ready, answer: (_) => call);

  @override
  ValueListenable<ModelStatus> get status => _status;

  @override
  Future<void> prepare() async {
    prepareCalls++;
    _status.value = const ModelStatus(ModelState.ready);
  }

  @override
  Future<ProposedCall?> propose(
    List<ModelTurn> conversation,
    List<FunctionDeclaration> functions,
  ) async {
    requests.add(conversation);
    offered.add([for (final f in functions) f.name]);
    return answer(conversation.last);
  }

  @override
  Future<void> release() async {}

  @override
  void dispose() {}
}

/// What a turn says, for comparing requests.
Object _shape(ModelTurn turn) => switch (turn) {
  UserTurn(:final text) => ['user', text],
  CallTurn(:final call) => ['call', call.name, call.args],
  ResponseTurn(:final name, :final response) => ['response', name, response],
  ReplyTurn(:final text) => ['reply', text],
};

const _biggerButtons = ProposedCall('change_button_size', {
  'direction': 'bigger',
});

final _tools = PersonalizationTools.fromJson(
  jsonDecode(File(PersonalizationTools.asset).readAsStringSync())
      as Map<String, Object?>,
);

final _buttonsHeuristic = Heuristic(
  id: 'near-miss-buttons',
  source: '',
  condition: const CountCondition(
    signal: SignalType.nearMiss,
    targetKind: TargetKind.button,
    minCount: 1,
    within: Duration(minutes: 5),
  ),
  category: ScaleCategory.button,
  steps: 1,
  cooldown: const Duration(minutes: 30),
  descriptions: const {'en': 'Buttons can be made bigger.'},
  rule: 'When buttons are hard to hit, make the buttons bigger.',
);

void main() {
  late AccessibilityController accessibility;
  late SuggestionManager manager;
  late int settingsOpened;
  late ThemeMode themeMode;
  late List<AssistChat> chats;
  late FakeActions actions;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    accessibility = AccessibilityController(store);
    manager = SuggestionManager(
      accessibility: accessibility,
      store: store,
      config: HeuristicsConfig(
        signals: const SignalConfig(),
        undoDuration: const Duration(seconds: 10),
        heuristics: [_buttonsHeuristic],
      ),
    );
    settingsOpened = 0;
    themeMode = ThemeMode.system;
    chats = const [
      AssistChat(id: '!maria', name: 'Maria Jensen'),
      AssistChat(id: '!peter', name: 'Peter', username: 'peter123'),
      AssistChat(id: '!family', name: 'Family'),
    ];
    manager.setThemeMode = (mode) async => themeMode = mode;
    actions = FakeActions();
  });

  tearDown(() {
    manager.dismissApplied();
    StudyLog.instance = null;
  });

  Future<void> pump(
    WidgetTester tester,
    FakeModel? model, {
    SpeechTranscriber? transcriber,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistView(
            model: model,
            transcriber: transcriber,
            manager: manager,
            accessibility: accessibility,
            onOpenAccessibilitySettings: () => settingsOpened++,
            tools: Future.value(_tools),
            themeMode: () => themeMode,
            chats: () => chats,
            actions: actions,
          ),
        ),
      ),
    );
    // The functions load after the first frame.
    await tester.pump();
  }

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('assist_input')), text);
    await tester.tap(find.byKey(const Key('assist_send')));
    await tester.pumpAndSettle();
  }

  FakeModel picksButtons() => FakeModel.calls(_biggerButtons);

  testWidgets('unavailable: explains and links to manual settings', (
    tester,
  ) async {
    await pump(tester, FakeModel(ModelState.unavailable));
    expect(find.textContaining("can't run on this phone"), findsOneWidget);
    expect(find.byKey(const Key('assist_input')), findsNothing);
    await tester.tap(find.byKey(const Key('assist_open_settings')));
    expect(settingsOpened, 1);
  });

  testWidgets('not prepared: set up, then the input appears', (tester) async {
    final model = FakeModel(ModelState.notPrepared);
    await pump(tester, model);
    expect(find.byKey(const Key('assist_input')), findsNothing);
    await tester.tap(find.byKey(const Key('assist_setup')));
    await tester.pump();
    expect(model.prepareCalls, 1);
    expect(find.byKey(const Key('assist_input')), findsOneWidget);
  });

  testWidgets('failed: retry prepares again', (tester) async {
    final model = FakeModel(ModelState.failed);
    await pump(tester, model);
    await tester.tap(find.byKey(const Key('assist_retry')));
    expect(model.prepareCalls, 1);
  });

  testWidgets('the model gets the prompt and exactly the trained functions', (
    tester,
  ) async {
    final model = picksButtons();
    await pump(tester, model);
    await ask(tester, 'the buttons are hard to hit');
    expect(model.requests.single.map(_shape), [
      ['user', 'the buttons are hard to hit'],
    ]);
    expect(model.offered.single, [
      'change_text_size',
      'change_button_size',
      'change_spacing',
      'change_line_spacing',
      'set_simple_mode',
      'set_button_labels',
      'set_high_contrast',
      'change_avatar_size',
      'set_theme',
      'set_read_aloud',
      'set_bubble_color',
      'set_app_color',
      'set_wallpaper',
      'set_gesture',
      'pin_chat',
      'mute_chat',
      'reset_settings',
      'ask_clarification',
      'no_action',
    ]);
  });

  testWidgets('a proposal shows text and preview but changes nothing', (
    tester,
  ) async {
    await pump(tester, picksButtons());
    await ask(tester, 'the buttons are hard to hit');
    expect(find.text('the buttons are hard to hit'), findsOneWidget);
    expect(find.text('Make all buttons bigger?'), findsOneWidget);
    expect(find.byKey(const Key('change_preview')), findsOneWidget);
    expect(find.byKey(const Key('assist_apply')), findsOneWidget);
    expect(find.byKey(const Key('assist_no_thanks')), findsOneWidget);
    expect(accessibility.settings, AccessibilitySettings.defaults);
  });

  testWidgets('apply changes the setting, then undo reverts it', (
    tester,
  ) async {
    await pump(tester, picksButtons());
    await ask(tester, 'the buttons are hard to hit');
    await tester.tap(find.byKey(const Key('assist_apply')));
    await tester.pumpAndSettle();
    expect(accessibility.settings.buttonScale, 1.2);
    expect(accessibility.settings.touchTargetScale, 1.2);
    expect(find.byKey(const Key('assist_undo')), findsOneWidget);

    await tester.tap(find.byKey(const Key('assist_undo')));
    await tester.pumpAndSettle();
    expect(accessibility.settings.buttonScale, 1.0);
    expect(find.text('The change was undone.'), findsOneWidget);
  });

  testWidgets('undo is offered only for the undo period', (tester) async {
    manager.config = HeuristicsConfig(
      signals: const SignalConfig(),
      undoDuration: const Duration(seconds: 3),
      heuristics: [_buttonsHeuristic],
    );
    await pump(tester, picksButtons());
    await ask(tester, 'the buttons are hard to hit');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('assist_apply')));
      await Future<void>.delayed(const Duration(milliseconds: 3500));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assist_undo')), findsNothing);
    expect(accessibility.settings.buttonScale, 1.2);
  });

  testWidgets('no thanks changes nothing', (tester) async {
    await pump(tester, picksButtons());
    await ask(tester, 'the buttons are hard to hit');
    await tester.tap(find.byKey(const Key('assist_no_thanks')));
    await tester.pumpAndSettle();
    expect(accessibility.settings, AccessibilitySettings.defaults);
    expect(find.text('Nothing was changed.'), findsOneWidget);
    expect(find.byKey(const Key('assist_apply')), findsNothing);
  });

  for (final (label, call) in [
    ('no call', null),
    ('an unknown function', const ProposedCall('delete_chat', {})),
    (
      'an old adjust function',
      const ProposedCall('adjust_text_size', {'direction': 'bigger'}),
    ),
    (
      'an unknown button',
      const ProposedCall('change_button_size', {
        'direction': 'bigger',
        'button': 'magnifying',
      }),
    ),
    (
      'a missing direction',
      const ProposedCall('change_text_size', {'steps': 2}),
    ),
  ]) {
    testWidgets('$label: no suggestion and a link to settings', (tester) async {
      await pump(tester, FakeModel(ModelState.ready, answer: (_) => call));
      await ask(tester, 'what is the weather');
      expect(find.text("I don't have a suggestion for that."), findsOneWidget);
      expect(manager.current, isNull);
      expect(accessibility.settings, AccessibilitySettings.defaults);
      await tester.tap(find.byKey(const Key('assist_open_settings')));
      expect(settingsOpened, 1);
    });
  }

  testWidgets('a model error gives no suggestion', (tester) async {
    await pump(
      tester,
      FakeModel(ModelState.ready, answer: (_) => throw StateError('boom')),
    );
    await ask(tester, 'the text is tiny');
    expect(find.text("I don't have a suggestion for that."), findsOneWidget);
    expect(manager.current, isNull);
  });

  testWidgets('a setting at its limit says so', (tester) async {
    // All buttons means the icons and the area that reacts to a tap.
    await accessibility.apply(ScaleCategory.button, ScaleCategory.button.max);
    await accessibility.apply(
      ScaleCategory.touchTarget,
      ScaleCategory.touchTarget.max,
    );
    await pump(tester, picksButtons());
    await ask(tester, 'the buttons are hard to hit');
    expect(find.textContaining('cannot change any further'), findsOneWidget);
    expect(find.byKey(const Key('assist_apply')), findsNothing);
  });

  testWidgets('nothing is proposed without a prompt', (tester) async {
    final model = picksButtons();
    await pump(tester, model);
    await tester.pumpAndSettle();
    expect(model.requests, isEmpty);
    expect(manager.current, isNull);
    expect(find.byKey(const Key('assist_apply')), findsNothing);
  });

  testWidgets('off in this study condition: no model, link to settings', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.textContaining('assistant is turned off'), findsOneWidget);
    expect(find.byKey(const Key('assist_input')), findsNothing);
    await tester.tap(find.byKey(const Key('assist_open_settings')));
    expect(settingsOpened, 1);
  });

  group('conversations', () {
    testWidgets('after apply, the next request carries the applied exchange', (
      tester,
    ) async {
      final model = picksButtons();
      await pump(tester, model);
      await ask(tester, 'the buttons are hard to hit');
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      await ask(tester, 'a lot more');
      expect(model.requests.last.map(_shape), [
        ['user', 'the buttons are hard to hit'],
        [
          'call',
          'change_button_size',
          {'direction': 'bigger'},
        ],
        [
          'response',
          'change_button_size',
          {'status': 'applied'},
        ],
        ['reply', 'Done.'],
        ['user', 'a lot more'],
      ]);
      manager.dismissApplied();
    });

    testWidgets('after no thanks, the next request carries the decline', (
      tester,
    ) async {
      final model = picksButtons();
      await pump(tester, model);
      await ask(tester, 'the buttons are hard to hit');
      await tester.tap(find.byKey(const Key('assist_no_thanks')));
      await tester.pumpAndSettle();
      await ask(tester, "no, I meant they're too close together");
      expect(model.requests.last.map(_shape), [
        ['user', 'the buttons are hard to hit'],
        [
          'call',
          'change_button_size',
          {'direction': 'bigger'},
        ],
        [
          'response',
          'change_button_size',
          {'status': 'declined'},
        ],
        ['reply', 'Okay, nothing changed.'],
        ['user', "no, I meant they're too close together"],
      ]);
    });

    testWidgets('a request without a change to answer starts fresh', (
      tester,
    ) async {
      final model = FakeModel.calls(const ProposedCall('no_action', {}));
      await pump(tester, model);
      await ask(tester, 'what time is it');
      expect(find.byKey(const Key('assist_no_action')), findsOneWidget);
      await ask(tester, 'the text is small');
      expect(model.requests.last.map(_shape), [
        ['user', 'the text is small'],
      ]);
    });

    testWidgets('a tapped option goes back as the answer in the same turn', (
      tester,
    ) async {
      final model = FakeModel(
        ModelState.ready,
        answer: (turn) => turn is UserTurn
            ? const ProposedCall('ask_clarification', {
                'options': ['change_text_size', 'change_avatar_size'],
              })
            : const ProposedCall('change_avatar_size', {'direction': 'bigger'}),
      );
      await pump(tester, model);
      await ask(tester, 'make it bigger');
      expect(find.byKey(const Key('assist_clarification')), findsOneWidget);
      expect(find.text('Text size'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('assist_option_change_avatar_size')),
      );
      await tester.pumpAndSettle();
      expect(model.requests.last.map(_shape), [
        ['user', 'make it bigger'],
        [
          'call',
          'ask_clarification',
          {
            'options': ['change_text_size', 'change_avatar_size'],
          },
        ],
        [
          'response',
          'ask_clarification',
          {'answer': 'change_avatar_size'},
        ],
      ]);
      expect(find.text('Make profile pictures bigger?'), findsOneWidget);
      // The options are answered.
      await tester.tap(find.byKey(const Key('assist_option_change_text_size')));
      await tester.pumpAndSettle();
      expect(model.requests, hasLength(2));
    });

    testWidgets('typed words answer an open question', (tester) async {
      final model = FakeModel(
        ModelState.ready,
        answer: (turn) => turn is UserTurn
            ? const ProposedCall('ask_clarification', {
                'options': ['change_text_size'],
              })
            : const ProposedCall('change_text_size', {
                'direction': 'bigger',
                'steps': 3,
              }),
      );
      await pump(tester, model);
      await ask(tester, 'change the text size');
      // One function: the choices are its details.
      expect(find.byKey(const Key('assist_option_bigger')), findsOneWidget);
      await ask(tester, 'much bigger');
      expect(model.requests.last.last, isA<ResponseTurn>());
      expect(_shape(model.requests.last.last), [
        'response',
        'ask_clarification',
        {'answer': 'much bigger'},
      ]);
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      expect(accessibility.settings.textScale, 1.5);
      manager.dismissApplied();
    });
  });

  group('the trained functions', () {
    Future<void> proposeAndApply(WidgetTester tester, ProposedCall call) async {
      await pump(tester, FakeModel.calls(call));
      await ask(tester, 'please');
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      manager.dismissApplied();
    }

    testWidgets('text size of one kind of text', (tester) async {
      await proposeAndApply(
        tester,
        const ProposedCall('change_text_size', {
          'direction': 'bigger',
          'target': 'chat_list',
          'steps': 3,
        }),
      );
      expect(accessibility.settings.chatListTextScale, 1.5);
      expect(accessibility.settings.textScale, 1.0);
    });

    testWidgets('one button', (tester) async {
      await proposeAndApply(
        tester,
        const ProposedCall('change_button_size', {
          'direction': 'bigger',
          'button': 'send',
        }),
      );
      expect(accessibility.settings[ScaleCategory.sendButton], 1.2);
      expect(accessibility.settings.buttonScale, 1.0);
    });

    testWidgets('spacing', (tester) async {
      await proposeAndApply(
        tester,
        const ProposedCall('change_spacing', {'direction': 'less'}),
      );
      expect(accessibility.settings.spacingScale, 0.75);
    });

    testWidgets('button labels and high contrast', (tester) async {
      await proposeAndApply(
        tester,
        const ProposedCall('set_button_labels', {'enabled': true}),
      );
      expect(accessibility.settings.buttonLabels, isTrue);
      await proposeAndApply(
        tester,
        const ProposedCall('set_high_contrast', {'enabled': true}),
      );
      expect(accessibility.settings.highContrast, isTrue);
    });

    testWidgets('theme, and undo puts it back', (tester) async {
      await pump(
        tester,
        FakeModel.calls(const ProposedCall('set_theme', {'mode': 'dark'})),
      );
      await ask(tester, 'the screen is too bright');
      expect(find.text('Switch to a dark screen?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      expect(themeMode, ThemeMode.dark);
      await tester.tap(find.byKey(const Key('assist_undo')));
      await tester.pumpAndSettle();
      expect(themeMode, ThemeMode.system);
    });

    testWidgets('reset keeps the theme', (tester) async {
      themeMode = ThemeMode.dark;
      await accessibility.apply(ScaleCategory.avatar, 1.5);
      await accessibility.setToggle(AccessibilityToggle.highContrast, true);
      await proposeAndApply(tester, const ProposedCall('reset_settings', {}));
      expect(accessibility.settings, AccessibilitySettings.defaults);
      expect(themeMode, ThemeMode.dark);
    });

    testWidgets('the simple view is not available and changes nothing', (
      tester,
    ) async {
      await pump(
        tester,
        FakeModel.calls(
          const ProposedCall('set_simple_mode', {'enabled': true}),
        ),
      );
      await ask(tester, 'too many buttons');
      expect(find.byKey(const Key('assist_not_available')), findsOneWidget);
      expect(manager.current, isNull);
      expect(accessibility.settings, AccessibilitySettings.defaults);
    });

    testWidgets('already as asked says so', (tester) async {
      await pump(
        tester,
        FakeModel.calls(const ProposedCall('set_theme', {'mode': 'system'})),
      );
      await ask(tester, 'follow my phone');
      expect(find.byKey(const Key('assist_unchanged')), findsOneWidget);
      expect(manager.current, isNull);
    });
  });

  group('one chat', () {
    testWidgets('a named chat that matches one chat is proposed at once', (
      tester,
    ) async {
      await pump(
        tester,
        FakeModel.calls(
          const ProposedCall('change_text_size', {
            'direction': 'bigger',
            'scope': 'one_chat',
            'chat': 'peter123',
          }),
        ),
      );
      await ask(tester, 'the text in my chat with peter123 is tiny');
      expect(
        find.text('Make the text in the chat with Peter bigger?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      expect(accessibility.settings.chatTextScale('!peter'), 1.2);
      expect(accessibility.settings.chatTextScale('!maria'), 1.0);
      expect(accessibility.settings.textScale, 1.0);
      manager.dismissApplied();
    });

    testWidgets('this chat: the app asks which one', (tester) async {
      final model = FakeModel.calls(
        const ProposedCall('change_text_size', {
          'direction': 'smaller',
          'scope': 'one_chat',
        }),
      );
      await pump(tester, model);
      await ask(tester, 'smaller text in this chat');
      expect(find.byKey(const Key('assist_which_chat')), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      await tester.tap(find.byKey(const Key('assist_chat_!family')));
      await tester.pumpAndSettle();
      // Chosen on the phone: the model is not asked again.
      expect(model.requests, hasLength(1));
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      expect(accessibility.settings.chatTextScale('!family'), 0.8);
      manager.dismissApplied();
    });

    testWidgets('a name that matches no chat asks which one', (tester) async {
      await pump(
        tester,
        FakeModel.calls(
          const ProposedCall('change_text_size', {
            'direction': 'bigger',
            'scope': 'one_chat',
            'chat': 'Dr. Hansen',
          }),
        ),
      );
      await ask(tester, 'bigger text with Dr. Hansen');
      expect(find.textContaining('“Dr. Hansen”'), findsOneWidget);
      expect(manager.current, isNull);
    });

    testWidgets('exact text size proposal says the size', (tester) async {
      await pump(
        tester,
        FakeModel.calls(
          const ProposedCall('change_text_size', {'size': '1.6'}),
        ),
      );
      await ask(tester, 'set the text to 1.6');
      expect(find.text('Set all text to 1.6?'), findsOneWidget);
    });
  });

  group('app changes', () {
    const simon = AssistChat(id: '!simon', name: 'Simon');
    const pinSimon = ProposedCall('pin_chat', {
      'chat': 'Simon',
      'enabled': true,
    });
    final red = Colors.red.toARGB32();

    testWidgets('pin: a named chat applies after Apply and undoes to the old '
        'value', (tester) async {
      chats = [...chats, simon];
      actions.values[(AppSetting.pinned, '!simon')] = false;
      await pump(tester, FakeModel.calls(pinSimon));
      await ask(tester, 'pin my chat with Simon');
      expect(find.text('Pin the chat with Simon?'), findsOneWidget);
      expect(actions.applied, isEmpty);
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      expect(actions.applied, [
        const AppChange(AppSetting.pinned, '!simon', true),
      ]);
      await tester.tap(find.byKey(const Key('assist_undo')));
      await tester.pumpAndSettle();
      expect(
        actions.applied.last,
        const AppChange(AppSetting.pinned, '!simon', false),
      );
      expect(find.text('The change was undone.'), findsOneWidget);
    });

    testWidgets('two chats called Simon show the chooser, not the first', (
      tester,
    ) async {
      chats = [simon, const AssistChat(id: '!simon2', name: 'Simon')];
      final model = FakeModel.calls(pinSimon);
      await pump(tester, model);
      await ask(tester, 'pin Simon');
      expect(find.byKey(const Key('assist_which_chat')), findsOneWidget);
      expect(find.byKey(const Key('assist_apply')), findsNothing);
      await tester.tap(find.byKey(const Key('assist_chat_!simon2')));
      await tester.pumpAndSettle();
      expect(model.requests, hasLength(1));
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      expect(actions.applied, [
        const AppChange(AppSetting.pinned, '!simon2', true),
      ]);
    });

    testWidgets('bubble side unclear asks mine or theirs', (tester) async {
      final model = FakeModel.calls(
        const ProposedCall('set_bubble_color', {'color': 'red'}),
      );
      await pump(tester, model);
      await ask(tester, 'make the bubbles red');
      expect(find.byKey(const Key('assist_detail_mine')), findsOneWidget);
      expect(find.byKey(const Key('assist_apply')), findsNothing);
      await tester.tap(find.byKey(const Key('assist_detail_theirs')));
      await tester.pumpAndSettle();
      // Chosen on the phone: the model is not asked again.
      expect(model.requests, hasLength(1));
      expect(
        find.text("Make other people's bubbles in all chats red?"),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      expect(actions.applied, [
        AppChange(AppSetting.otherBubbleColor, null, red),
      ]);
    });

    testWidgets('a color the other side already has is refused', (
      tester,
    ) async {
      actions.values[(AppSetting.otherBubbleColor, null)] = red;
      await pump(
        tester,
        FakeModel.calls(
          const ProposedCall('set_bubble_color', {
            'color': 'red',
            'side': 'mine',
          }),
        ),
      );
      await ask(tester, 'make my bubbles red');
      expect(
        find.text(
          'The other side already has that color, so the bubbles would look '
          'the same. Pick another color.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('assist_apply')), findsNothing);
      expect(actions.applied, isEmpty);
    });

    testWidgets('only the latest applied app change can be undone', (
      tester,
    ) async {
      final blue = Colors.blue.toARGB32();
      actions.values[(AppSetting.ownBubbleColor, null)] = blue;
      await pump(
        tester,
        FakeModel(
          ModelState.ready,
          answer: (turn) => ProposedCall('set_bubble_color', {
            'color': turn is UserTurn && turn.text.contains('my')
                ? 'red'
                : 'blue',
            'side': turn is UserTurn && turn.text.contains('my')
                ? 'mine'
                : 'theirs',
          }),
        ),
      );
      await ask(tester, 'make my bubbles red');
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      await ask(tester, "make other people's bubbles blue");
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      // Undoing the first would make both sides blue.
      expect(find.byKey(const Key('assist_undo')), findsOneWidget);
      await tester.tap(find.byKey(const Key('assist_undo')));
      await tester.pumpAndSettle();
      expect(actions.applied, [
        AppChange(AppSetting.ownBubbleColor, null, red),
        AppChange(AppSetting.otherBubbleColor, null, blue),
        const AppChange(AppSetting.otherBubbleColor, null, null),
      ]);
      expect(find.byKey(const Key('assist_undo')), findsNothing);
    });

    testWidgets('already pinned says already set', (tester) async {
      chats = [...chats, simon];
      actions.values[(AppSetting.pinned, '!simon')] = true;
      await pump(tester, FakeModel.calls(pinSimon));
      await ask(tester, 'pin Simon');
      expect(find.text('That is already how it is.'), findsOneWidget);
      expect(find.byKey(const Key('assist_apply')), findsNothing);
    });

    testWidgets('no thanks applies nothing', (tester) async {
      await pump(
        tester,
        FakeModel.calls(
          const ProposedCall('set_gesture', {
            'gesture': 'autoplay_gifs',
            'enabled': false,
          }),
        ),
      );
      await ask(tester, 'stop the gifs moving');
      expect(find.text('Turn off playing GIFs by themselves?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('assist_no_thanks')));
      await tester.pumpAndSettle();
      expect(actions.applied, isEmpty);
      expect(find.text('Nothing was changed.'), findsOneWidget);
    });
  });

  group('study log', () {
    late StudySettings settings;
    late MemoryStorage storage;

    setUp(() async {
      settings = StudySettings(await SharedPreferences.getInstance());
      await settings.update(settings.value.copyWith(logging: true));
      storage = MemoryStorage();
    });

    // Made in the test body, so the log's writes run in the test's fake
    // async zone.
    void startLog() =>
        StudyLog.instance = StudyLog(settings: settings, storage: storage);

    List<Map<String, Object?>> events() => [
      for (final line in storage.lines)
        jsonDecode(line) as Map<String, Object?>,
    ];

    testWidgets('records the prompt, the answer with timing and the outcome', (
      tester,
    ) async {
      startLog();
      final model = picksButtons()
        ..lastTiming = const ModelTiming(
          totalMs: 900,
          timeToFirstTokenMs: 410.4,
          backend: 'gpu',
        );
      await pump(tester, model);
      await ask(tester, 'the buttons are hard to hit');
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assist_undo')));
      await tester.pumpAndSettle();

      expect(
        [for (final e in events()) e['type']],
        [
          'assist_prompt',
          'assist_proposal',
          'suggestion_applied',
          'suggestion_undone',
        ],
      );
      expect(events()[0]['prompt'], 'the buttons are hard to hit');
      expect(events()[1], {
        't': isA<String>(),
        'type': 'assist_proposal',
        'participant': '',
        'function': 'change_button_size',
        'arguments': {'direction': 'bigger'},
        'changes': {
          'button_scale': [1.0, 1.2],
          'touch_target_scale': [1.0, 1.2],
        },
        'total_ms': 900,
        'ttft_ms': 410,
        'backend': 'gpu',
      });
      expect(events()[2], containsPair('function', 'change_button_size'));
    });

    testWidgets('records app changes without the chat', (tester) async {
      startLog();
      chats = [...chats, const AssistChat(id: '!simon', name: 'Simon')];
      await pump(
        tester,
        FakeModel.calls(
          const ProposedCall('mute_chat', {'chat': 'Simon', 'enabled': true}),
        ),
      );
      await ask(tester, 'mute Simon');
      await tester.tap(find.byKey(const Key('assist_apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assist_undo')));
      await tester.pumpAndSettle();
      expect(
        [
          for (final e in events())
            if (e['type'] == 'assist_app_change') e['action'],
        ],
        ['apply', 'undo'],
      );
      expect(events().last, containsPair('setting', 'muted'));
      // The prompt is the only text kept.
      final lines = storage.lines.skip(1).join();
      expect(lines, isNot(contains('!simon')));
      expect(lines, isNot(contains('Simon')));
    });

    testWidgets('records no suggestion with its reason', (tester) async {
      startLog();
      await pump(
        tester,
        FakeModel(
          ModelState.ready,
          answer: (turn) => turn is UserTurn && turn.text == 'boom'
              ? throw StateError('boom')
              : const ProposedCall('delete_chat', {}),
        ),
      );
      await ask(tester, 'delete my chats');
      await ask(tester, 'boom');
      expect([for (final e in events()) e['reason']].nonNulls.toList(), [
        'unknownFunction',
        'error',
      ]);
    });

    testWidgets('records when the model changes state', (tester) async {
      startLog();
      final model = FakeModel(ModelState.notPrepared);
      await pump(tester, model);
      await tester.tap(find.byKey(const Key('assist_setup')));
      await tester.pumpAndSettle();
      expect(events().single, containsPair('state', 'ready'));
    });

    testWidgets('a spoken prompt is only recorded once it is sent', (
      tester,
    ) async {
      startLog();
      final voice = FakeTranscriber();
      await pump(tester, picksButtons(), transcriber: voice);
      await tester.tap(find.byKey(const Key('assist_mic')));
      await tester.pump();
      voice.hear('the buttons are hard to hit');
      await tester.tap(find.byKey(const Key('assist_mic')));
      await tester.pumpAndSettle();
      expect(events().where((e) => e['type'] == 'assist_prompt'), isEmpty);
      await tester.tap(find.byKey(const Key('assist_send')));
      await tester.pumpAndSettle();
      expect(events().where((e) => e['type'] == 'assist_prompt').single, {
        't': isA<String>(),
        'type': 'assist_prompt',
        'participant': '',
        'prompt': 'the buttons are hard to hit',
        'voice': true,
      });
    });

    List<Object?> voiceFlags() => [
      for (final e in events())
        if (e['type'] == 'assist_prompt') e['voice'],
    ];

    testWidgets('voice stays true after editing and resets after send', (
      tester,
    ) async {
      startLog();
      final voice = FakeTranscriber();
      await pump(tester, picksButtons(), transcriber: voice);
      await tester.tap(find.byKey(const Key('assist_mic')));
      await tester.pump();
      voice.hear('the buttons are hard');
      await tester.tap(find.byKey(const Key('assist_mic')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('assist_input')),
        'the buttons are hard to hit',
      );
      await tester.tap(find.byKey(const Key('assist_send')));
      await tester.pumpAndSettle();
      await ask(tester, 'the text is tiny');
      expect(voiceFlags(), [true, false]);
    });

    testWidgets('clearing the field resets voice', (tester) async {
      startLog();
      final voice = FakeTranscriber();
      await pump(tester, picksButtons(), transcriber: voice);
      await tester.tap(find.byKey(const Key('assist_mic')));
      await tester.pump();
      voice.hear('something else');
      await tester.tap(find.byKey(const Key('assist_mic')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('assist_input')), '');
      await ask(tester, 'the buttons are hard to hit');
      expect(voiceFlags(), [false]);
    });

    testWidgets('a cancelled recording does not count as voice', (
      tester,
    ) async {
      startLog();
      final voice = FakeTranscriber();
      await pump(tester, picksButtons(), transcriber: voice);
      await tester.enterText(find.byKey(const Key('assist_input')), 'the');
      await tester.tap(find.byKey(const Key('assist_mic')));
      await tester.pump();
      voice.hear('buttons');
      await tester.pump();
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await ask(tester, 'the buttons are hard to hit');
      expect(voiceFlags(), [false]);
    });
  });

  group('voice input', () {
    late FakeTranscriber voice;

    setUp(() => voice = FakeTranscriber());

    Finder mic() => find.byKey(const Key('assist_mic'));
    Finder micIcon(IconData icon) =>
        find.descendant(of: mic(), matching: find.byIcon(icon));
    TextField field(WidgetTester tester) =>
        tester.widget<TextField>(find.byKey(const Key('assist_input')));
    bool sendEnabled(WidgetTester tester) =>
        tester
            .widget<IconButton>(find.byKey(const Key('assist_send')))
            .onPressed !=
        null;
    bool micEnabled(WidgetTester tester) =>
        tester.widget<IconButton>(mic()).onPressed != null;

    Future<void> tapMic(WidgetTester tester) async {
      await tester.tap(mic());
      await tester.pump();
    }

    testWidgets('no mic without a transcriber or when it is unavailable', (
      tester,
    ) async {
      final model = picksButtons();
      await pump(tester, model);
      expect(mic(), findsNothing);

      await pump(
        tester,
        model,
        transcriber: FakeTranscriber(status: TranscriberStatus.unavailable),
      );
      expect(mic(), findsNothing);
      await ask(tester, 'the buttons are hard to hit');
      expect(model.prompts, ['the buttons are hard to hit']);
      expect(find.byKey(const Key('assist_apply')), findsOneWidget);
    });

    testWidgets('the mic sits before send and has a large touch target', (
      tester,
    ) async {
      await pump(tester, picksButtons(), transcriber: voice);
      expect(micIcon(Icons.mic), findsOneWidget);
      final micBox = tester.getRect(mic());
      final sendBox = tester.getRect(find.byKey(const Key('assist_send')));
      expect(micBox.right, lessThanOrEqualTo(sendBox.left));
      expect(micBox.width, greaterThanOrEqualTo(48));
      expect(micBox.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the mic follows the accessibility scales like send', (
      tester,
    ) async {
      await accessibility.apply(
        ScaleCategory.touchTarget,
        ScaleCategory.touchTarget.max,
      );
      await accessibility.apply(ScaleCategory.button, ScaleCategory.button.max);
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityScope(
            controller: accessibility,
            child: AccessibilityIconButtons(
              child: Scaffold(
                body: AssistView(
                  model: picksButtons(),
                  transcriber: voice,
                  manager: manager,
                  accessibility: accessibility,
                  onOpenAccessibilitySettings: () {},
                  tools: Future.value(_tools),
                  themeMode: () => themeMode,
                  chats: () => chats,
                  actions: actions,
                ),
              ),
            ),
          ),
        ),
      );
      final micSize = tester.getSize(mic());
      expect(micSize, tester.getSize(find.byKey(const Key('assist_send'))));
      expect(micSize.width, greaterThan(48));
      expect(
        tester.getSize(micIcon(Icons.mic)),
        tester.getSize(find.byIcon(Icons.send)),
      );
    });

    testWidgets('tapping the mic records, with a stop icon and a timer', (
      tester,
    ) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tapMic(tester);
      expect(voice.startCalls, 1);
      expect(micIcon(Icons.stop), findsOneWidget);
      expect(micIcon(Icons.mic), findsNothing);
      expect(find.text('Listening. Tap to stop.'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0:03'), findsOneWidget);
      expect(field(tester).readOnly, isTrue);
      expect(sendEnabled(tester), isFalse);
      await tapMic(tester);
    });

    testWidgets('a session the platform ends does not end the recording', (
      tester,
    ) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tapMic(tester);
      voice.hear('make the buttons');
      await tester.pump();
      expect(field(tester).controller?.text, 'make the buttons');
      voice.endSession();
      voice.hear('bigger');
      await tester.pump();
      expect(find.text('Listening. Tap to stop.'), findsOneWidget);
      expect(micIcon(Icons.stop), findsOneWidget);
      expect(field(tester).controller?.text, 'make the buttons bigger');
      expect(voice.sessions, 2);
      expect(voice.stopCalls, 0);
      await tapMic(tester);
    });

    testWidgets('stop shows finishing, then leaves the text to edit', (
      tester,
    ) async {
      final model = picksButtons();
      await pump(tester, model, transcriber: voice..holdStop = true);
      await tapMic(tester);
      voice.hear('the buttons are hard to hit');
      await tapMic(tester);
      expect(voice.stopCalls, 1);
      expect(find.text('Writing down what you said…'), findsOneWidget);
      expect(micEnabled(tester), isFalse);
      expect(sendEnabled(tester), isFalse);

      voice.completeStop();
      await tester.pumpAndSettle();
      expect(micIcon(Icons.mic), findsOneWidget);
      expect(field(tester).controller?.text, 'the buttons are hard to hit');
      expect(field(tester).readOnly, isFalse);
      expect(sendEnabled(tester), isTrue);
      expect(model.prompts, isEmpty);

      await tester.tap(find.byKey(const Key('assist_send')));
      await tester.pumpAndSettle();
      expect(model.prompts, ['the buttons are hard to hit']);
    });

    testWidgets('spoken words go after the text already in the field', (
      tester,
    ) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tester.enterText(
        find.byKey(const Key('assist_input')),
        'the buttons ',
      );
      await tapMic(tester);
      voice.hear('are too small');
      await tester.pump();
      expect(field(tester).controller?.text, 'the buttons are too small');
      await tapMic(tester);
      expect(field(tester).controller?.text, 'the buttons are too small');
    });

    testWidgets('an empty result leaves the field unchanged', (tester) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tester.enterText(find.byKey(const Key('assist_input')), 'hello ');
      await tapMic(tester);
      await tapMic(tester);
      expect(field(tester).controller?.text, 'hello ');
      expect(find.text('I did not hear anything. Try again.'), findsOneWidget);
    });

    testWidgets('an error stops the recording, keeps the text, says so', (
      tester,
    ) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tapMic(tester);
      voice.hear('make it');
      voice.fail(TranscriberEnd.error);
      await tester.pump();
      expect(micIcon(Icons.mic), findsOneWidget);
      expect(field(tester).controller?.text, 'make it');
      expect(find.textContaining('because of a problem'), findsOneWidget);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('a missing language pack hides the mic and explains', (
      tester,
    ) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tapMic(tester);
      voice.fail(TranscriberEnd.languageMissing, unavailable: true);
      await tester.pump();
      expect(mic(), findsNothing);
      expect(find.textContaining('offline speech recognition'), findsOne);
      expect(find.byKey(const Key('assist_input')), findsOneWidget);
    });

    testWidgets('while the pack downloads, the mic waits and typing works', (
      tester,
    ) async {
      final model = picksButtons();
      voice.statusValue = TranscriberStatus.preparing;
      await pump(tester, model, transcriber: voice);
      expect(micIcon(Icons.downloading), findsOneWidget);
      expect(micEnabled(tester), isFalse);
      expect(find.textContaining('downloading English speech'), findsOne);
      expect(sendEnabled(tester), isTrue);
      // The download spinner never settles, so pump by hand.
      await tester.enterText(
        find.byKey(const Key('assist_input')),
        'the buttons are hard to hit',
      );
      await tester.tap(find.byKey(const Key('assist_send')));
      await tester.pump();
      expect(model.prompts, ['the buttons are hard to hit']);

      voice.statusValue = TranscriberStatus.ready;
      await tester.pump();
      expect(micIcon(Icons.mic), findsOneWidget);
      expect(micEnabled(tester), isTrue);
      expect(find.textContaining('downloading English speech'), findsNothing);
    });

    testWidgets('the missing-pack message goes once the pack arrives', (
      tester,
    ) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tapMic(tester);
      voice.fail(TranscriberEnd.languageMissing, unavailable: true);
      await tester.pump();
      expect(find.textContaining('offline speech recognition'), findsOne);
      voice.statusValue = TranscriberStatus.preparing;
      await tester.pump();
      expect(find.textContaining('downloading English speech'), findsOne);
      voice.statusValue = TranscriberStatus.ready;
      await tester.pump();
      expect(find.textContaining('offline speech recognition'), findsNothing);
      expect(micEnabled(tester), isTrue);
    });

    testWidgets('a denied permission explains and typing still works', (
      tester,
    ) async {
      final model = picksButtons();
      await pump(tester, model, transcriber: voice);
      await tapMic(tester);
      voice.fail(TranscriberEnd.permissionDenied);
      await tester.pump();
      expect(
        find.textContaining('allow the app to use the microphone'),
        findsOne,
      );
      await ask(tester, 'the buttons are hard to hit');
      expect(model.prompts, ['the buttons are hard to hit']);
    });

    testWidgets('the time limit keeps the text and says so', (tester) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tapMic(tester);
      voice.hear('a very long request');
      voice.reachTimeLimit();
      await tester.pump();
      expect(field(tester).controller?.text, 'a very long request');
      expect(find.textContaining('after 2 minutes'), findsOneWidget);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('backgrounding the app cancels the recording', (tester) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tester.enterText(find.byKey(const Key('assist_input')), 'hi');
      await tapMic(tester);
      voice.hear('there');
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(voice.cancelCalls, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(voice.cancelCalls, 1);
      expect(field(tester).controller?.text, 'hi');
      expect(micIcon(Icons.mic), findsOneWidget);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('leaving the tab during a recording cancels it', (
      tester,
    ) async {
      await pump(tester, picksButtons(), transcriber: voice);
      await tapMic(tester);
      await tester.pumpWidget(const SizedBox());
      expect(voice.cancelCalls, 1);
    });
  });
}
