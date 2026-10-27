// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/signals/interaction_monitor.dart';
import 'package:fluffychat/personalization/signals/tracked_target.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('nothing suggests a change without a prompt', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppSettings.init(loadWebConfigFile: false);
    final controller = AccessibilityController(store);

    await tester.pumpWidget(
      AccessibilityScope(
        controller: controller,
        child: MaterialApp(
          builder: (context, child) => PersonalizationLayer(child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 100,
                  width: 48,
                  height: 48,
                  child: TrackedTarget(
                    id: 'send',
                    kind: TargetKind.button,
                    child: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Let the heuristics file load.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    final manager = PersonalizationLayer.maybeManagerOf(
      tester.element(find.byType(Scaffold)),
    )!;
    expect(manager.config.heuristics, isNotEmpty);

    // Many near misses, which used to trigger a suggestion.
    for (var i = 0; i < 20; i++) {
      await tester.tapAt(const Offset(160, 124));
      await tester.pump(const Duration(milliseconds: 700));
    }
    await tester.pumpAndSettle();

    expect(find.byType(InteractionMonitor), findsNothing);
    expect(find.byType(SuggestionCard), findsNothing);
    expect(manager.current, isNull);
    expect(controller.settings.buttonScale, 1.0);
  });
}
