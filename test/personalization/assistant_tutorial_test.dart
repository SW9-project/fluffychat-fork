// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assistant_tutorial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences store;
  var openedSettings = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    openedSettings = 0;
  });

  Widget app(Widget child, {double scale = 1}) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  );

  Widget gate() => AssistantTutorialGate(
    store: store,
    onOpenSettings: () => openedSettings++,
    child: const Text('Assistant screen'),
  );

  Future<void> tap(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(Key('assistant_tutorial_$name')));
    await tester.pumpAndSettle();
  }

  Future<void> practice(WidgetTester tester, String action) async {
    final button = find.byKey(Key('tutorial_example_$action'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('practice previews, applies and undoes without saving settings', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(gate()));
    await tester.pumpAndSettle();
    await tap(tester, 'next');
    expect(find.byKey(const Key('tutorial_example_apply')), findsNothing);
    await practice(tester, 'ask');
    expect(find.byKey(const Key('tutorial_sample_current')), findsOneWidget);
    expect(find.byKey(const Key('tutorial_sample_larger')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Suggested. Larger text. Your message'),
      findsOneWidget,
    );
    await practice(tester, 'apply');
    expect(find.text('The example text is bigger.'), findsOneWidget);
    expect(find.byKey(const Key('tutorial_sample_larger')), findsOneWidget);
    expect(store.getKeys(), isEmpty);
    await practice(tester, 'undo');
    expect(find.text('Back to the original size.'), findsOneWidget);
    expect(find.byKey(const Key('tutorial_sample_larger')), findsNothing);
    expect(find.byKey(const Key('tutorial_sample_current')), findsOneWidget);
    expect(store.getKeys(), isEmpty);
    expect(openedSettings, 0);
    await tap(tester, 'skip');
    expect(store.getKeys(), {assistantTutorialPendingKey});
    semantics.dispose();
  });

  testWidgets('first visit offers three steps without changing app settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(gate()));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tap(tester, 'next');
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('“Make the text bigger”'), findsOneWidget);
    await tap(tester, 'back');
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tap(tester, 'next');
    await tap(tester, 'next');
    expect(find.text('Step 3 of 3'), findsOneWidget);
    await tap(tester, 'next');
    expect(find.text('Assistant screen'), findsOneWidget);
    expect(store.getBool(assistantTutorialPendingKey), isFalse);
    expect(store.getKeys(), {assistantTutorialPendingKey});
    expect(openedSettings, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(gate()));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsNothing);
  });

  testWidgets('skip dismisses and does not reopen on the next visit', (
    tester,
  ) async {
    await tester.pumpWidget(app(gate()));
    await tester.pumpAndSettle();
    await tap(tester, 'skip');
    expect(store.getBool(assistantTutorialPendingKey), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(gate()));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsNothing);
  });

  testWidgets('Settings can disable, replay and re-arm the tutorial', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AssistantTutorialSettings(
          store: store,
          onOpenSettings: () => openedSettings++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'toggle');
    expect(store.getBool(assistantTutorialPendingKey), isFalse);
    await tester.tap(find.text('Assistant tutorial'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tap(tester, 'skip');
    await tap(tester, 'toggle');
    expect(store.getBool(assistantTutorialPendingKey), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(gate()));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tap(tester, 'skip');
  });

  testWidgets('last step opens real accessibility settings only on request', (
    tester,
  ) async {
    await tester.pumpWidget(app(gate()));
    await tester.pumpAndSettle();
    await tap(tester, 'next');
    await tap(tester, 'next');
    await tester.ensureVisible(
      find.byKey(const Key('assistant_tutorial_settings')),
    );
    await tap(tester, 'settings');
    expect(openedSettings, 1);
    expect(find.text('Step 3 of 3'), findsNothing);
    expect(store.getBool(assistantTutorialPendingKey), isFalse);
  });

  testWidgets(
    'large text on narrow screens keeps controls and content reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accessibility = AccessibilityController(store);
      addTearDown(accessibility.dispose);
      await tester.runAsync(
        () => accessibility.apply(ScaleCategory.touchTarget, 2),
      );
      await tester.pumpWidget(
        AccessibilityScope(
          controller: accessibility,
          child: app(gate(), scale: 2),
        ),
      );
      await tester.pumpAndSettle();
      for (var step = 0; step < 3; step++) {
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getSize(find.byKey(const Key('assistant_tutorial_next')))
              .height,
          greaterThanOrEqualTo(96),
        );
        expect(
          find.byKey(const Key('assistant_tutorial_skip')).hitTestable(),
          findsOneWidget,
        );
        if (step == 1) {
          await practice(tester, 'ask');
          await practice(tester, 'apply');
          await practice(tester, 'undo');
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('assistant_tutorial_skip')).hitTestable(),
            findsOneWidget,
          );
        }
        if (step == 2) {
          await tester.ensureVisible(
            find.byKey(const Key('assistant_tutorial_settings')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tap(tester, 'next');
      }
      expect(store.getBool(assistantTutorialPendingKey), isFalse);
    },
  );
}
