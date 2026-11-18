// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/personalization_tools.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/quick_access_conversations.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:fluffychat/personalization/simple_view_conversations.dart';
import 'package:fluffychat/personalization/simple_view_setup.dart';
import 'package:fluffychat/personalization/simplified_interface.dart';
import 'package:fluffychat/personalization/simplified_interface_widgets.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assist_view_test.dart' show FakeModel;

void main() {
  late SharedPreferences store;
  late SimplifiedInterfaceController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    controller = SimplifiedInterfaceController(store);
  });
  tearDown(() {
    controller.dispose();
    StudyLog.instance = null;
  });

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    // Allow each queued platform write to finish before relaunch assertions.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  test(
    'mode persists independently and rapid changes preserve latest choice',
    () async {
      expect(controller.enabled, false);
      final writes = [
        controller.setEnabled(true),
        controller.setEnabled(false),
        controller.setEnabled(true),
      ];
      await Future.wait(writes);
      final restored = SimplifiedInterfaceController(store);
      expect(restored.enabled, true);
      expect(controller.revision, 3);
      expect(store.getKeys(), {SimplifiedInterfaceController.enabledKey});
      restored.dispose();
    },
  );
  test(
    'shortcuts are deduplicated, capped, stable, and account-specific',
    () async {
      await controller.setQuickAccess('account-a', [
        'b',
        'a',
        'b',
        '',
        'c',
        'd',
      ]);
      await controller.setQuickAccess('account-b', ['z']);
      final restored = SimplifiedInterfaceController(store);
      expect(restored.quickAccessFor('account-a'), ['b', 'a', 'c']);
      expect(restored.quickAccessFor('account-b'), ['z']);
      expect(controller.enabled, false);
      restored.dispose();
    },
  );
  test('invalid saved shortcuts are ignored', () async {
    await store.setString(
      SimplifiedInterfaceController.quickAccessKey,
      'broken',
    );
    expect(controller.quickAccessFor('a'), isEmpty);
  });
  testWidgets('switch fits a narrow screen at double text scale', (
    tester,
  ) async {
    controller.applyPreferences(
      const SimpleViewPreferences(),
      enabled: false,
      skipPreview: true,
    );
    await tester.pump();
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SimplifiedInterfaceScope(
          controller: controller,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: SingleChildScrollView(child: SimplifiedInterfaceSwitch()),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('simplified_interface_switch')));
    await tester.pumpAndSettle();
    expect(controller.enabled, true);
    expect(tester.takeException(), null);
  });
  Future<void> pumpHome(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: SimplifiedInterfaceScope(
          controller: controller,
          child: const Scaffold(
            body: SingleChildScrollView(child: SimplifiedInterfaceSwitch()),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'onboarding remains usable at double text scale on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpHome(tester, textScale: 2);
      await tap(tester, 'simplified_interface_switch');
      for (var step = 0; step < 2; step++) {
        await tap(tester, 'simple_setup_next');
      }
      await tap(tester, 'simple_skip_preview');
      expect(tester.takeException(), null);
      await tap(tester, 'simple_setup_cancel');
      expect(controller.enabled, false);
    },
  );

  testWidgets(
    'first activation asks two questions and saves only after preview confirmation',
    (tester) async {
      await pumpHome(tester);
      await tap(tester, 'simplified_interface_switch');
      expect(controller.enabled, false);
      await tap(tester, 'setup_frequent');
      await tap(tester, 'simple_setup_next');
      await tap(tester, 'setup_detailed_home');
      await tap(tester, 'simple_setup_next');
      expect(controller.configured, false);
      expect(controller.enabled, false);
      await tap(tester, 'simple_skip_preview');
      await tap(tester, 'simple_setup_apply');
      expect(controller.enabled, true);
      expect(controller.preferences.quickAccess, SimpleQuickAccess.frequent);
      expect(controller.preferences.cleanHome, false);
      expect(controller.skipPreview, true);
      await tap(tester, 'simplified_interface_switch');
      expect(controller.enabled, false);
      expect(find.byKey(const Key('simple_setup_apply')), findsNothing);
      final restored = SimplifiedInterfaceController(store);
      expect(restored.configured, true);
      expect(restored.skipPreview, true);
      expect(restored.preferences.cleanHome, false);
      restored.dispose();
    },
  );

  testWidgets('cancel discards onboarding choices and preview preference', (
    tester,
  ) async {
    await pumpHome(tester);
    await tap(tester, 'simplified_interface_switch');
    await tap(tester, 'setup_frequent');
    await tap(tester, 'simple_setup_next');
    await tap(tester, 'simple_setup_next');
    await tap(tester, 'simple_skip_preview');
    await tap(tester, 'simple_setup_cancel');
    expect(controller.configured, false);
    expect(controller.enabled, false);
    expect(controller.skipPreview, false);
    expect(store.getKeys(), isEmpty);
  });

  testWidgets(
    'later switch changes show a cancellable preview without repeating questions',
    (tester) async {
      controller.applyPreferences(
        const SimpleViewPreferences(),
        enabled: false,
        skipPreview: false,
      );
      await tester.pump();
      await pumpHome(tester);
      await tap(tester, 'simplified_interface_switch');
      expect(find.byKey(const Key('setup_frequent')), findsNothing);
      expect(find.byKey(const Key('simple_setup_apply')), findsOneWidget);
      expect(controller.enabled, false);
      await tap(tester, 'simple_skip_preview');
      await tap(tester, 'simple_setup_cancel');
      expect(controller.skipPreview, false);
      expect(controller.enabled, false);
    },
  );

  testWidgets('Personalize can restore previews and update choices', (
    tester,
  ) async {
    controller.applyPreferences(
      const SimpleViewPreferences(),
      enabled: true,
      skipPreview: true,
    );
    await tester.pump();
    await pumpHome(tester);
    await tap(tester, 'simple_personalize');
    await tap(tester, 'setup_none');
    await tap(tester, 'simple_setup_next');
    await tap(tester, 'simple_setup_next');
    await tap(tester, 'simple_skip_preview');
    await tap(tester, 'simple_setup_apply');
    expect(controller.preferences.quickAccess, SimpleQuickAccess.none);
    expect(controller.skipPreview, false);
    await tap(tester, 'simplified_interface_switch');
    expect(controller.enabled, true);
    await tap(tester, 'simple_setup_cancel');
    expect(controller.enabled, true);
  });

  testWidgets('Change is hidden in full view and the preview is step 3 of 3', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('simple_personalize')), findsNothing);
    await tap(tester, 'simplified_interface_switch');
    await tap(tester, 'simple_setup_next');
    await tap(tester, 'simple_setup_next');
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Try simple view?'), findsOneWidget);
    await tap(tester, 'simple_setup_apply');
    expect(find.byKey(const Key('simple_personalize')), findsOneWidget);
  });

  test(
    'frequent shortcuts count opted-in openings per account and survive restart',
    () async {
      await controller.applyPreferences(
        const SimpleViewPreferences(quickAccess: SimpleQuickAccess.frequent),
        enabled: true,
        skipPreview: false,
      );
      expect(controller.frequentFor('a', ['one', 'two', 'three', 'four']), [
        'one',
        'two',
        'three',
      ]);
      await controller.recordConversationOpened('a', 'four');
      await controller.recordConversationOpened('a', 'four');
      expect(controller.frequentFor('a', ['one', 'two', 'three', 'four']), [
        'four',
        'one',
        'two',
      ]);
      expect(controller.frequentFor('b', ['one', 'two', 'three', 'four']), [
        'one',
        'two',
        'three',
      ]);
      final restored = SimplifiedInterfaceController(store);
      expect(restored.frequentFor('a', ['one', 'two', 'three', 'four']), [
        'four',
        'one',
        'two',
      ]);
      restored.dispose();
      await controller.setEnabled(false);
      await controller.recordConversationOpened('a', 'three');
      expect(controller.frequentFor('a', ['one', 'two', 'three', 'four']), [
        'four',
        'one',
        'two',
      ]);
    },
  );

  Future<void> pumpContactSetup(WidgetTester tester) async {
    final source = SimpleViewConversations('account-a', [
      for (final name in ['Anna', 'Beth', 'Carla', 'David'])
        QuickAccessConversation(id: name, name: name, onOpen: () {}),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open_setup'),
              onPressed: () => requestSimpleViewChange(
                context,
                controller,
                true,
                conversations: source,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, 'open_setup');
  }

  testWidgets('frequent choice shows the actual three names before applying', (
    tester,
  ) async {
    await pumpContactSetup(tester);
    await tap(tester, 'setup_frequent');
    for (final name in ['Anna', 'Beth', 'Carla']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('David'), findsNothing);
    await tap(tester, 'simple_setup_cancel');
    expect(controller.configured, false);
  });

  testWidgets('chosen names are transactional across picker and onboarding', (
    tester,
  ) async {
    await pumpContactSetup(tester);
    await tap(tester, 'setup_choose_names');
    await tap(tester, 'quick_access_pick_David');
    await tap(tester, 'quick_access_pick_Anna');
    await tap(tester, 'quick_access_save');
    expect(find.text('David'), findsOneWidget);
    expect(controller.quickAccessFor('account-a'), isEmpty);
    await tap(tester, 'simple_setup_cancel');
    expect(controller.quickAccessFor('account-a'), isEmpty);
    await tap(tester, 'open_setup');
    await tap(tester, 'setup_choose_names');
    await tap(tester, 'quick_access_pick_Beth');
    await tap(tester, 'quick_access_save');
    expect(find.text('Beth'), findsOneWidget);
    await tap(tester, 'simple_setup_next');
    await tap(tester, 'simple_setup_next');
    expect(find.byKey(const Key('setup_familiar_chat')), findsNothing);
    await tap(tester, 'simple_setup_apply');
    expect(controller.quickAccessFor('account-a'), ['Beth']);
    expect(controller.quickAccessFor('account-b'), isEmpty);
    final restored = SimplifiedInterfaceController(store);
    expect(restored.quickAccessFor('account-a'), ['Beth']);
    restored.dispose();
  });

  testWidgets(
    'dialog keeps personalized scaling outside the navigator and never resets sizes',
    (tester) async {
      final sizes = AccessibilityController(store);
      await sizes.apply(ScaleCategory.text, 1.8);
      await sizes.apply(ScaleCategory.button, 1.4);
      final before = sizes.settings;
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityScope(
            controller: sizes,
            child: AccessibilityTextScale(
              child: SimplifiedInterfaceScope(
                controller: controller,
                child: const Scaffold(body: SimplifiedInterfaceSwitch()),
              ),
            ),
          ),
        ),
      );
      await tap(tester, 'simplified_interface_switch');
      final heading = tester.element(find.text('Conversations at the top'));
      expect(MediaQuery.textScalerOf(heading).scale(10), closeTo(18, 0.01));
      expect(AccessibilityScope.of(heading).buttonScale, 1.4);
      await tap(tester, 'simple_setup_next');
      await tap(tester, 'simple_setup_next');
      await tap(tester, 'simple_setup_apply');
      expect(sizes.settings, before);
      expect(AccessibilitySettings.load(store), before);
      await tester.pumpWidget(const SizedBox.shrink());
      sizes.dispose();
    },
  );

  testWidgets('picker limits selection and cancel keeps original shortcuts', (
    tester,
  ) async {
    List<String>? saved;
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickAccessConversations(
            conversations: [
              for (final id in ['a', 'b', 'c', 'd'])
                QuickAccessConversation(
                  id: id,
                  name: id,
                  onOpen: () => opened = id,
                ),
            ],
            selectedIds: const ['b'],
            onSave: (ids) => saved = ids,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('quick_access_b')));
    expect(opened, 'b');
    await tester.tap(find.byKey(const Key('quick_access_choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_access_pick_a')));
    await tester.tap(find.byKey(const Key('quick_access_pick_c')));
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('quick_access_pick_d')),
          )
          .onChanged,
      null,
    );
    await tester.tap(find.byKey(const Key('quick_access_cancel')));
    await tester.pumpAndSettle();
    expect(saved, null);
    await tester.tap(find.byKey(const Key('quick_access_choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_access_pick_a')));
    await tester.tap(find.byKey(const Key('quick_access_save')));
    await tester.pumpAndSettle();
    expect(saved, ['b', 'a']);
  });

  Future<SuggestionManager> pumpAssistant(
    WidgetTester tester,
    FakeModel model, {
    bool configured = true,
  }) async {
    if (configured) {
      controller.applyPreferences(
        const SimpleViewPreferences(),
        enabled: false,
        skipPreview: false,
      );
    }
    await tester.pump();
    final accessibility = AccessibilityController(store);
    final manager = SuggestionManager(
      accessibility: accessibility,
      store: store,
      config: const HeuristicsConfig(
        signals: SignalConfig(),
        undoDuration: Duration(seconds: 10),
        heuristics: [],
      ),
    );
    addTearDown(manager.dismissApplied);
    await tester.pumpWidget(
      MaterialApp(
        home: SimplifiedInterfaceScope(
          controller: controller,
          child: Scaffold(
            body: AssistView(
              model: model,
              manager: manager,
              accessibility: accessibility,
              onOpenAccessibilitySettings: () {},
              tools: Future.value(
                PersonalizationTools.fromJson(
                  jsonDecode(
                        File(PersonalizationTools.asset).readAsStringSync(),
                      )
                      as Map<String, Object?>,
                ),
              ),
              themeMode: () => ThemeMode.system,
              chats: () => const [],
            ),
          ),
        ),
      ),
    );
    // The functions load after the first frame.
    await tester.pump();
    return manager;
  }

  testWidgets(
    'Assistant first activation uses the same onboarding and supports Undo',
    (tester) async {
      await pumpAssistant(
        tester,
        FakeModel(ModelState.ready),
        configured: false,
      );
      await tap(tester, 'assist_simple_view');
      await tap(tester, 'assist_simple_apply');
      expect(controller.enabled, false);
      expect(find.byKey(const Key('setup_frequent')), findsOneWidget);
      for (var step = 0; step < 2; step++) {
        await tap(tester, 'simple_setup_next');
      }
      await tap(tester, 'simple_setup_apply');
      expect(controller.enabled, true);
      expect(controller.configured, true);
      await tap(tester, 'assist_simple_undo');
      expect(controller.enabled, false);
      expect(controller.configured, true);
    },
  );

  testWidgets(
    'Assistant explicit action previews, applies and undoes without invoking model',
    (tester) async {
      final model = FakeModel(ModelState.ready);
      await pumpAssistant(tester, model);
      await tap(tester, 'assist_simple_view');
      expect(controller.enabled, false);
      expect(model.requests, isEmpty);
      await tap(tester, 'assist_simple_apply');
      expect(controller.enabled, true);
      await tap(tester, 'assist_simple_undo');
      expect(controller.enabled, false);
    },
  );
  testWidgets(
    'manual toggles invalidate an unapplied preview even after returning to the same mode',
    (tester) async {
      await pumpAssistant(tester, FakeModel(ModelState.ready));
      await tap(tester, 'assist_simple_view');
      controller.setEnabled(true);
      controller.setEnabled(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assist_simple_apply')), findsNothing);
      expect(controller.enabled, false);
    },
  );
  testWidgets('a later manual choice invalidates Undo', (tester) async {
    await pumpAssistant(tester, FakeModel(ModelState.ready));
    await tap(tester, 'assist_simple_view');
    await tap(tester, 'assist_simple_apply');
    controller.setEnabled(false);
    controller.setEnabled(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assist_simple_undo')), findsNothing);
    expect(controller.enabled, true);
  });
  testWidgets(
    'trained model tool follows the same preview and confirmation path',
    (tester) async {
      final model = FakeModel(
        ModelState.ready,
        answer: (_) => const ProposedCall('set_simple_mode', {'enabled': true}),
      );
      await pumpAssistant(tester, model);
      await tester.enterText(
        find.byKey(const Key('assist_input')),
        'Simplify the screen',
      );
      await tap(tester, 'assist_send');
      expect(model.offered.single, contains('set_simple_mode'));
      expect(controller.enabled, false);
      await tap(tester, 'assist_simple_apply');
      expect(controller.enabled, true);
    },
  );
}
