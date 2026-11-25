// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/assistant_tutorial.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/personalization_tools.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assist_view_test.dart' show FakeModel;
import 'fake_actions.dart';

/// Answers only once [answer] completes, to see the wait.
class _SlowModel extends FakeModel {
  final reply = Completer<void>();
  _SlowModel()
    : super(
        ModelState.ready,
        answer: (_) =>
            const ProposedCall('change_text_size', {'direction': 'bigger'}),
      );

  @override
  Future<ProposedCall?> propose(
    List<ModelTurn> conversation,
    List<FunctionDeclaration> functions,
  ) async {
    await reply.future;
    return super.propose(conversation, functions);
  }
}

final _tools = PersonalizationTools.fromJson(
  jsonDecode(File(PersonalizationTools.asset).readAsStringSync())
      as Map<String, Object?>,
);

void main() {
  late SharedPreferences store;
  late AccessibilityController accessibility;
  late SuggestionManager manager;
  late AssistantGuide guide;
  var openedSettings = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    accessibility = AccessibilityController(store);
    manager = SuggestionManager(
      accessibility: accessibility,
      store: store,
      config: const HeuristicsConfig(
        signals: SignalConfig(),
        undoDuration: Duration(minutes: 1),
        heuristics: [],
      ),
    );
    guide = AssistantGuide(store: store);
    openedSettings = 0;
  });

  tearDown(() => manager.dismissApplied());

  FakeModel biggerText([ModelState state = ModelState.ready]) => FakeModel(
    state,
    answer: (_) =>
        const ProposedCall('change_text_size', {'direction': 'bigger'}),
  );

  Widget app(FakeModel? model, {double scale = 1}) => AccessibilityScope(
    controller: accessibility,
    child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: AssistView(
          model: model,
          manager: manager,
          accessibility: accessibility,
          onOpenAccessibilitySettings: () => openedSettings++,
          tools: Future.value(_tools),
          themeMode: () => ThemeMode.system,
          chats: () => const [],
          actions: FakeActions(),
          guide: guide,
        ),
      ),
    ),
  );

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  String hint(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('assistant_guide_hint'))).data!;

  bool spotlit(String key) => find
      .ancestor(
        of: find.byKey(Key(key)),
        matching: find.byKey(const Key('assistant_guide_spotlight')),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('the example runs for real in the Assistant, then undoes', (
    tester,
  ) async {
    final model = biggerText();
    await tester.pumpWidget(app(model));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant_guide')), findsOneWidget);
    expect(find.text('Meet Assistant · Step 1 of 3'), findsOneWidget);
    // The real prompt field is usable while the guide is open.
    expect(find.byKey(const Key('assist_input')), findsOneWidget);

    await tap(tester, 'assistant_tutorial_next');
    expect(find.text('Make the text bigger'), findsOneWidget);
    expect(spotlit('assist_send'), isTrue);
    expect(hint(tester), contains('Tap Ask'));

    await tap(tester, 'assist_send');
    expect(model.prompts, ['Make the text bigger']);
    expect(spotlit('assist_apply'), isTrue);
    expect(spotlit('assist_send'), isFalse);
    expect(accessibility.settings, AccessibilitySettings.defaults);

    await tap(tester, 'assist_apply');
    expect(accessibility.settings, isNot(AccessibilitySettings.defaults));
    expect(spotlit('assist_undo'), isTrue);
    expect(hint(tester), contains('Undo'));

    await tap(tester, 'assist_undo');
    expect(accessibility.settings, AccessibilitySettings.defaults);
    expect(hint(tester), startsWith('Everything is back'));

    await tap(tester, 'assistant_tutorial_next');
    expect(find.text('Meet Assistant · Step 3 of 3'), findsOneWidget);
    await tap(tester, 'assistant_tutorial_next');
    expect(find.byKey(const Key('assistant_guide')), findsNothing);
    expect(store.getBool(assistantTutorialPendingKey), isFalse);
    expect(AssistantGuide(store: store).step, isNull);
    expect(openedSettings, 0);
  });

  testWidgets('the guide waits out the answer, then explains the preview', (
    tester,
  ) async {
    final model = _SlowModel();
    await tester.pumpWidget(app(model));
    await tester.pumpAndSettle();
    await tap(tester, 'assistant_tutorial_next');
    await tester.tap(find.byKey(const Key('assist_send')));
    await tester.pump();
    expect(find.byKey(const Key('assistant_guide')), findsNothing);

    model.reply.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant_guide')), findsOneWidget);
    expect(hint(tester), contains('preview'));
    expect(hint(tester), contains('No thanks'));
    expect(spotlit('assist_apply'), isTrue);
    expect(spotlit('assist_no_thanks'), isTrue);

    await tap(tester, 'assist_no_thanks');
    expect(accessibility.settings, AccessibilitySettings.defaults);
    expect(hint(tester), startsWith('The change was discarded'));
    expect(spotlit('assist_no_thanks'), isFalse);
  });

  testWidgets('back keeps the field, and a typed prompt is not replaced', (
    tester,
  ) async {
    await tester.pumpWidget(app(biggerText()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('assist_input')), 'my words');
    await tap(tester, 'assistant_tutorial_next');
    expect(find.text('my words'), findsOneWidget);
    await tap(tester, 'assistant_tutorial_back');
    expect(find.text('Meet Assistant · Step 1 of 3'), findsOneWidget);
  });

  testWidgets('skip closes the guide for good; replay starts it again', (
    tester,
  ) async {
    await tester.pumpWidget(app(biggerText()));
    await tester.pumpAndSettle();
    await tap(tester, 'assistant_tutorial_skip');
    expect(find.byKey(const Key('assistant_guide')), findsNothing);
    expect(store.getBool(assistantTutorialPendingKey), isFalse);
    expect(AssistantGuide(store: store).step, isNull);
    guide.start();
    await tester.pumpAndSettle();
    expect(find.text('Meet Assistant · Step 1 of 3'), findsOneWidget);
  });

  testWidgets('the guide waits until the AI is set up', (tester) async {
    await tester.pumpWidget(app(biggerText(ModelState.notPrepared)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assist_setup')), findsOneWidget);
    expect(find.byKey(const Key('assistant_guide')), findsNothing);
    await tap(tester, 'assist_setup');
    expect(find.text('Meet Assistant · Step 1 of 3'), findsOneWidget);
    expect(store.getBool(assistantTutorialPendingKey), isNull);
  });

  testWidgets('last step opens accessibility settings only on request', (
    tester,
  ) async {
    await tester.pumpWidget(app(biggerText()));
    await tester.pumpAndSettle();
    await tap(tester, 'assistant_tutorial_next');
    await tap(tester, 'assistant_tutorial_next');
    expect(openedSettings, 0);
    await tap(tester, 'assistant_tutorial_settings');
    expect(openedSettings, 1);
    expect(find.byKey(const Key('assistant_guide')), findsNothing);
    expect(store.getBool(assistantTutorialPendingKey), isFalse);
  });

  testWidgets('large text on a narrow screen keeps the real controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => accessibility.apply(ScaleCategory.touchTarget, 2),
    );
    await tester.pumpWidget(app(biggerText(), scale: 2));
    await tester.pumpAndSettle();
    for (var step = 0; step < 3; step++) {
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('assistant_tutorial_skip')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assist_send')).hitTestable(),
        findsOneWidget,
      );
      final next = find.byKey(const Key('assistant_tutorial_next'));
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      expect(tester.getSize(next).height, greaterThanOrEqualTo(96));
      await tap(tester, 'assistant_tutorial_next');
    }
    expect(store.getBool(assistantTutorialPendingKey), isFalse);
  });
}
