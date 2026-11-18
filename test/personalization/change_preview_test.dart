// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/change_preview.dart';
import 'package:fluffychat/personalization/suggestions/suggestion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const defaults = AccessibilitySettings.defaults;

  // A small phone: 360 dp wide, with the padding of the Assist answer.
  Future<void> pump(WidgetTester tester, SettingsChange change) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ChangePreview(change: change),
          ),
        ),
      ),
    );
  }

  double height(WidgetTester tester, String text, int index) =>
      tester.getRect(find.text(text).at(index)).height;

  for (final (category, sample) in [
    (ScaleCategory.text, 'Hi! Are we still meeting tomorrow at 10?'),
    (ScaleCategory.messageText, 'Hi! Are we still meeting tomorrow at 10?'),
    (ScaleCategory.inputText, 'Write a message'),
  ]) {
    testWidgets('${category.id}: the suggested text is bigger on a phone', (
      tester,
    ) async {
      await pump(tester, SettingsChange.scale(defaults, category, 1.3));
      expect(find.text(sample), findsAtLeastNWidgets(2));
      // On-screen size of the same sample, now and suggested.
      final count = find.text(sample).evaluate().length;
      expect(
        height(tester, sample, count - 1),
        greaterThan(height(tester, sample, 0) * 1.15),
      );
    });
  }

  testWidgets('one chat: the suggested message text is bigger', (tester) async {
    await pump(
      tester,
      SettingsChange(from: defaults, to: defaults.withChatText('!room', 1.5)),
    );
    const sample = 'Hi! Are we still meeting tomorrow at 10?';
    expect(height(tester, sample, 1), greaterThan(height(tester, sample, 0)));
  });

  testWidgets('a size change shows the current and the new size', (
    tester,
  ) async {
    await pump(
      tester,
      SettingsChange.scale(defaults, ScaleCategory.button, 1.3),
    );
    expect(find.text('Now · Button size: × 1.0'), findsOneWidget);
    expect(find.text('Suggested · Button size: × 1.3'), findsOneWidget);
  });

  testWidgets('one chat: shows the current and the new size', (tester) async {
    await pump(
      tester,
      SettingsChange(from: defaults, to: defaults.withChatText('!room', 1.5)),
    );
    expect(find.textContaining('× 1.00'), findsOneWidget);
    expect(find.textContaining('× 1.50'), findsOneWidget);
  });

  testWidgets('labels: shown only on the suggested side', (tester) async {
    await pump(
      tester,
      SettingsChange(
        from: defaults,
        to: defaults.withToggle(AccessibilityToggle.buttonLabels, true),
      ),
    );
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('theme: the suggested side is dark', (tester) async {
    await pump(
      tester,
      const SettingsChange(
        from: defaults,
        to: defaults,
        themeFrom: ThemeMode.light,
        themeTo: ThemeMode.dark,
      ),
    );
    final themes = tester
        .widgetList<Theme>(
          find.descendant(
            of: find.byKey(const Key('change_preview')),
            matching: find.byType(Theme),
          ),
        )
        .map((t) => t.data.brightness);
    expect(themes, contains(Brightness.dark));
    expect(tester.takeException(), isNull);
  });

  for (final category in ScaleCategory.values) {
    testWidgets('${category.id}: the largest change fits a phone', (
      tester,
    ) async {
      await pump(
        tester,
        SettingsChange(
          from: defaults.copyWith(category, category.min),
          to: defaults.copyWith(category, category.max),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('change_preview')), findsOneWidget);
    });
  }

  testWidgets('everything at once fits a phone', (tester) async {
    var to = defaults
        .withToggle(AccessibilityToggle.buttonLabels, true)
        .withToggle(AccessibilityToggle.highContrast, true);
    for (final c in ScaleCategory.values) {
      to = to.copyWith(c, c.max);
    }
    await pump(tester, SettingsChange(from: defaults, to: to));
    expect(tester.takeException(), isNull);
  });
}
