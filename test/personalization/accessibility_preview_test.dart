// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/accessibility_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AccessibilityController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    controller = AccessibilityController(await SharedPreferences.getInstance());
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AccessibilityScope(
        controller: controller,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AccessibilityPreview()),
          ),
        ),
      ),
    );
  }

  // The drawn size of each icon in the preview's input row and top bar.
  Map<String, double> iconSizes(WidgetTester tester) => {
    for (final (name, icon) in [
      ('emoji', Icons.emoji_emotions_outlined),
      ('attach', Icons.add),
      ('back', Icons.arrow_back),
      ('menu', Icons.adaptive.more),
    ])
      name: tester.getSize(find.byIcon(icon)).width,
  };

  testWidgets('changing one button resizes only that button', (tester) async {
    await pump(tester);
    final before = iconSizes(tester);

    await controller.apply(ScaleCategory.emojiButton, 1.5);
    // Buttons animate to their new size.
    await tester.pumpAndSettle();
    final after = iconSizes(tester);

    expect(after['emoji'], before['emoji']! * 1.5);
    for (final other in ['attach', 'back', 'menu']) {
      expect(after[other], before[other], reason: other);
    }
  });

  testWidgets('the send button shows when only its size changed', (
    tester,
  ) async {
    await controller.apply(ScaleCategory.sendButton, 1.5);
    await pump(tester);
    expect(tester.getSize(find.byIcon(Icons.send)).width, 24 * 1.5);
  });

  testWidgets('the button size resizes every button', (tester) async {
    await pump(tester);
    final before = iconSizes(tester);

    await controller.apply(ScaleCategory.button, 1.5);
    // Buttons animate to their new size.
    await tester.pumpAndSettle();
    final after = iconSizes(tester);

    for (final name in before.keys) {
      expect(after[name], before[name]! * 1.5, reason: name);
    }
  });
}
