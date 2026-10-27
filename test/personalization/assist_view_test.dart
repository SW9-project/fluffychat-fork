// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/settings_functions.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> pump(WidgetTester tester, FakeModel? model) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AssistView(
          model: model,
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
  });
}
