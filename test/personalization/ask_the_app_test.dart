// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/ask_the_app_section.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:fluffychat/personalization/suggestions/suggestion.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeModel implements SettingsIntentModel {
  final ValueNotifier<ModelStatus> _status;
  ProposedCall? Function(String text) answer;
  int prepareCalls = 0;
  final List<String> asked = [];

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
  Future<ProposedCall?> propose(String text) async {
    asked.add(text);
    return answer(text);
  }

  @override
  Future<void> release() async {}

  @override
  void dispose() {}
}

void main() {
  late AccessibilityController accessibility;
  late SuggestionManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    accessibility = AccessibilityController(store);
    manager = SuggestionManager(accessibility: accessibility, store: store);
  });

  Future<void> pump(WidgetTester tester, FakeModel model) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AskTheAppSection(
          model: model,
          manager: manager,
          accessibility: accessibility,
        ),
      ),
    ),
  );

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('ask_input')), text);
    await tester.tap(find.byKey(const Key('ask_send')));
    await tester.pumpAndSettle();
  }

  testWidgets('hidden when the model cannot run', (tester) async {
    await pump(tester, FakeModel(ModelState.unavailable));
    expect(find.text('Tell the app what is hard'), findsNothing);
    expect(find.byKey(const Key('ask_input')), findsNothing);
  });

  testWidgets('the input appears only after setup', (tester) async {
    final model = FakeModel(ModelState.notPrepared);
    await pump(tester, model);
    expect(find.byKey(const Key('ask_input')), findsNothing);
    await tester.tap(find.byKey(const Key('ask_setup')));
    await tester.pump();
    expect(model.prepareCalls, 1);
    expect(find.byKey(const Key('ask_input')), findsOneWidget);
  });

  testWidgets('a valid call becomes a suggestion, not a change', (
    tester,
  ) async {
    final model = FakeModel(
      ModelState.ready,
      answer: (_) =>
          const ProposedCall('adjust_button_size', {'direction': 'bigger'}),
    );
    await pump(tester, model);
    await ask(tester, 'the buttons are too small');

    expect(model.asked, ['the buttons are too small']);
    final suggestion = manager.current!;
    expect(suggestion.isUserRequest, isTrue);
    expect(suggestion.category, ScaleCategory.button);
    expect(suggestion.to, 1.1);
    expect(suggestion.description('en'), contains('the buttons are too small'));
    // Nothing applies until the user confirms on the card.
    expect(accessibility.settings, AccessibilitySettings.defaults);

    await manager.apply();
    expect(accessibility.settings.buttonScale, 1.1);
    manager.dismissApplied();
  });

  testWidgets('no call shows the fallback with a hint to the sliders', (
    tester,
  ) async {
    await pump(tester, FakeModel(ModelState.ready));
    await ask(tester, 'what is the weather');
    expect(find.byKey(const Key('ask_feedback')), findsOneWidget);
    expect(find.textContaining('sliders'), findsOneWidget);
    expect(manager.current, isNull);
  });

  testWidgets('an unknown function is rejected', (tester) async {
    final model = FakeModel(
      ModelState.ready,
      answer: (_) => const ProposedCall('delete_chat', {}),
    );
    await pump(tester, model);
    await ask(tester, 'delete everything');
    expect(find.byKey(const Key('ask_feedback')), findsOneWidget);
    expect(manager.current, isNull);
  });

  testWidgets('a model error shows the fallback', (tester) async {
    final model = FakeModel(
      ModelState.ready,
      answer: (_) => throw StateError('boom'),
    );
    await pump(tester, model);
    await ask(tester, 'the text is tiny');
    expect(find.byKey(const Key('ask_feedback')), findsOneWidget);
    expect(manager.current, isNull);
  });

  testWidgets('a change past the limit says so', (tester) async {
    final model = FakeModel(
      ModelState.ready,
      answer: (_) =>
          const ProposedCall('adjust_button_size', {'direction': 'smaller'}),
    );
    await pump(tester, model);
    await ask(tester, 'smaller buttons');
    expect(find.textContaining('cannot change any further'), findsOneWidget);
  });

  test('user requests ignore cooldowns and replace open suggestions', () async {
    final heuristic = Heuristic(
      id: 'h',
      source: '',
      condition: const CountCondition(
        signal: SignalType.pinch,
        targetKind: null,
        minCount: 1,
        within: Duration(minutes: 5),
      ),
      category: ScaleCategory.text,
      steps: 1,
      cooldown: const Duration(minutes: 30),
      descriptions: const {'en': 'h'},
    );
    manager.config = HeuristicsConfig(
      signals: const SignalConfig(),
      undoDuration: const Duration(seconds: 10),
      heuristics: [heuristic],
    );
    manager.addSignal(InteractionSignal(SignalType.pinch, DateTime.now()));
    expect(manager.current?.id, 'h');

    const request = Suggestion(
      id: Suggestion.modelRequestId,
      descriptions: {'en': 'asked'},
      cooldown: Duration.zero,
      category: ScaleCategory.avatar,
      from: 1.0,
      to: 1.1,
    );
    manager.proposeUserRequest(request);
    expect(manager.current, same(request));
    manager.notNow();
    manager.proposeUserRequest(request);
    expect(manager.current, same(request));
  });
}
