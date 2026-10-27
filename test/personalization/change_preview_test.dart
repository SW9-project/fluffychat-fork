// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/change_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // A small phone: 360 dp wide, with the padding of the Assist answer.
  Future<void> pump(
    WidgetTester tester,
    ScaleCategory category,
    double from,
    double to,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(32),
            child: ChangePreview(category: category, from: from, to: to),
          ),
        ),
      ),
    );
  }

  for (final (category, sample) in [
    (ScaleCategory.text, 'Yes, see you then!'),
    (ScaleCategory.inputText, 'Write a message'),
  ]) {
    testWidgets('${category.id}: the suggested text is bigger on a phone', (
      tester,
    ) async {
      await pump(tester, category, 1.0, 1.2);
      final samples = find.text(sample);
      expect(samples, findsNWidgets(2));
      // On-screen size, after any scaling by the layout.
      final now = tester.getRect(samples.at(0)).height;
      final suggested = tester.getRect(samples.at(1)).height;
      expect(suggested, greaterThan(now * 1.15));
    });
  }

  for (final category in ScaleCategory.values) {
    testWidgets('${category.id}: the largest change fits a phone', (
      tester,
    ) async {
      await pump(tester, category, category.min, category.max);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('change_preview')), findsOneWidget);
    });
  }
}
