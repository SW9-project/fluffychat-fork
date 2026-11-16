// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/settings_functions.dart';
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

import 'fake_transcriber.dart';

class MemoryStorage implements StudyLogStorage {
  final List<String> lines = [];

  @override
  Future<void> append(String line) async => lines.add(line);

  @override
  Future<List<String>> readLines() async => [...lines];
}

class FakeModel implements SettingsIntentModel {
  final ValueNotifier<ModelStatus> _status;
  ProposedCall? Function(String text) answer;
  int prepareCalls = 0;
  final List<String> prompts = [];
  final List<List<String>> offered = [];

  @override
  ModelTiming? lastTiming;

  FakeModel(ModelState state, {ProposedCall? Function(String)? answer})
    : _status = ValueNotifier(ModelStatus(state)),
      answer = answer ?? ((_) => null);

  @override
  ValueListenable<ModelStatus> get status => _status;

  @override
  Future<void> prepare() async {
    prepareCalls++;
    _status.value = const ModelStatus(ModelState.ready);
  }

  @override
  Future<ProposedCall?> propose(
    String text,
    List<FunctionDeclaration> functions,
  ) async {
    prompts.add(text);
    offered.add([for (final f in functions) f.name]);
    return answer(text);
  }

  @override
  Future<void> release() async {}

  @override
  void dispose() {}
}

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
  });

  tearDown(() {
    manager.dismissApplied();
    StudyLog.instance = null;
  });

  Future<void> pump(
    WidgetTester tester,
    FakeModel? model, {
    SpeechTranscriber? transcriber,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AssistView(
          model: model,
          transcriber: transcriber,
          manager: manager,
          accessibility: accessibility,
          onOpenAccessibilitySettings: () => settingsOpened++,
        ),
      ),
    ),
  );

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('assist_input')), text);
    await tester.tap(find.byKey(const Key('assist_send')));
    await tester.pumpAndSettle();
  }

  FakeModel picksButtons() => FakeModel(
    ModelState.ready,
    answer: (_) => const ProposedCall('heuristic_near_miss_buttons', {}),
  );

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

  testWidgets('the model gets only the prompt and the heuristic functions', (
    tester,
  ) async {
    final model = picksButtons();
    await pump(tester, model);
    await ask(tester, 'the buttons are hard to hit');
    expect(model.prompts, ['the buttons are hard to hit']);
    expect(model.offered.single, ['heuristic_near_miss_buttons']);
  });

  testWidgets('a proposal shows text and preview but changes nothing', (
    tester,
  ) async {
    await pump(tester, picksButtons());
    await ask(tester, 'the buttons are hard to hit');
    expect(find.text('the buttons are hard to hit'), findsOneWidget);
    expect(find.text('Buttons can be made bigger.'), findsOneWidget);
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
    expect(accessibility.settings.buttonScale, 1.1);
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
    expect(accessibility.settings.buttonScale, 1.1);
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
    await accessibility.apply(ScaleCategory.button, ScaleCategory.button.max);
    await pump(tester, picksButtons());
    await ask(tester, 'the buttons are hard to hit');
    expect(find.textContaining('cannot change any further'), findsOneWidget);
    expect(find.byKey(const Key('assist_apply')), findsNothing);
  });

  testWidgets('nothing is proposed without a prompt', (tester) async {
    final model = picksButtons();
    await pump(tester, model);
    await tester.pumpAndSettle();
    expect(model.prompts, isEmpty);
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
        'heuristic': 'near-miss-buttons',
        'category': 'button_scale',
        'from': 1.0,
        'to': 1.1,
        'total_ms': 900,
        'ttft_ms': 410,
        'backend': 'gpu',
      });
      expect(events()[2], containsPair('to', 1.1));
    });

    testWidgets('records no suggestion with its reason', (tester) async {
      startLog();
      await pump(
        tester,
        FakeModel(
          ModelState.ready,
          answer: (text) => text == 'boom'
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
