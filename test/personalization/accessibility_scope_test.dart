// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AccessibilityController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    controller = AccessibilityController(await SharedPreferences.getInstance());
  });

  Widget app(Widget child) => AccessibilityScope(
    controller: controller,
    child: MaterialApp(
      home: AccessibilityTextScale(child: Scaffold(body: child)),
    ),
  );

  testWidgets('text scale multiplies the system text scale', (tester) async {
    late TextScaler scaler;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: app(
          Builder(
            builder: (context) {
              scaler = MediaQuery.textScalerOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(scaler.scale(10), 15);

    await controller.apply(ScaleCategory.text, 2.0);
    await tester.pump();
    expect(scaler.scale(10), 30);
  });

  testWidgets('icon buttons follow button and touch target scale', (
    tester,
  ) async {
    const key = Key('button');
    await tester.pumpWidget(
      app(
        Center(
          child: AccessibilityIconButtons(
            child: IconButton(
              key: key,
              onPressed: () {},
              icon: const Icon(Icons.send),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byIcon(Icons.send)), const Size.square(24));
    final defaultSize = tester.getSize(find.byKey(key));

    await controller.apply(ScaleCategory.button, 2.0);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byIcon(Icons.send)), const Size.square(48));

    await controller.apply(ScaleCategory.touchTarget, 2.0);
    await tester.pumpAndSettle();
    final scaledSize = tester.getSize(find.byKey(key));
    expect(scaledSize.width, greaterThan(defaultSize.width));
    expect(scaledSize.width, greaterThanOrEqualTo(80));
  });

  testWidgets('without a scope the defaults are used', (tester) async {
    late AccessibilitySettings settings;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          settings = AccessibilityScope.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(settings, AccessibilitySettings.defaults);
  });
}
