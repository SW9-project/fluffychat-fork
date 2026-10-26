// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/signals/interaction_monitor.dart';
import 'package:fluffychat/personalization/signals/interaction_signal.dart';
import 'package:fluffychat/personalization/signals/tracked_target.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_card.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('InteractionMonitor', () {
    late List<InteractionSignal> signals;

    Future<void> pump(WidgetTester tester) async {
      signals = [];
      await tester.pumpWidget(
        MaterialApp(
          home: InteractionMonitor(
            config: const SignalConfig(nearMissDistance: 16),
            onSignal: signals.add,
            child: Scaffold(
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
                  const Positioned(
                    left: 0,
                    top: 300,
                    width: 400,
                    height: 300,
                    child: TrackedTarget(
                      id: 'timeline',
                      kind: TargetKind.text,
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('records hits and near misses without blocking taps', (
      tester,
    ) async {
      await pump(tester);
      await tester.tapAt(const Offset(124, 124));
      await tester.tapAt(const Offset(160, 124));
      await tester.tapAt(const Offset(390, 50));
      expect(signals.map((s) => s.type), [SignalType.hit, SignalType.nearMiss]);
      expect(signals.every((s) => s.targetId == 'send'), isTrue);
    });

    testWidgets('a two-finger spread on text is a pinch', (tester) async {
      await pump(tester);
      final a = await tester.startGesture(const Offset(180, 450), pointer: 1);
      final b = await tester.startGesture(const Offset(220, 450), pointer: 2);
      await a.moveTo(const Offset(120, 450));
      await b.moveTo(const Offset(280, 450));
      await a.up();
      await b.up();
      expect(signals.map((s) => s.type), [SignalType.pinch]);
      expect(signals.single.targetId, 'timeline');
    });

    testWidgets('a two-finger squeeze is not a pinch', (tester) async {
      await pump(tester);
      final a = await tester.startGesture(const Offset(100, 450), pointer: 1);
      final b = await tester.startGesture(const Offset(300, 450), pointer: 2);
      await a.moveTo(const Offset(180, 450));
      await b.moveTo(const Offset(220, 450));
      await a.up();
      await b.up();
      expect(signals, isEmpty);
    });
  });

  group('SuggestionCard', () {
    late AccessibilityController accessibility;
    late SuggestionManager manager;

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
          heuristics: [
            Heuristic(
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
              descriptions: const {'en': 'Make the buttons bigger?'},
            ),
          ],
        ),
      );
    });

    Future<void> showSuggestion(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SuggestionCard(manager))),
      );
      manager.addSignal(
        InteractionSignal(
          SignalType.nearMiss,
          DateTime.now(),
          kind: TargetKind.button,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the premade text and the change', (tester) async {
      await showSuggestion(tester);
      expect(find.text('Make the buttons bigger?'), findsOneWidget);
      expect(find.text('Button size'), findsOneWidget);
      expect(find.text('× 1.0'), findsOneWidget);
      expect(find.text('× 1.1'), findsOneWidget);
      expect(accessibility.settings.buttonScale, 1.0);
    });

    testWidgets('apply, then undo from the card', (tester) async {
      await showSuggestion(tester);
      await tester.tap(find.byKey(const Key('suggestion_apply')));
      await tester.pumpAndSettle();
      expect(accessibility.settings.buttonScale, 1.1);
      expect(find.text('Button size is now × 1.1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('suggestion_undo')));
      await tester.pumpAndSettle();
      expect(accessibility.settings.buttonScale, 1.0);
      expect(find.byKey(const Key('suggestion_undo')), findsNothing);
    });

    testWidgets('not now hides the card without changes', (tester) async {
      await showSuggestion(tester);
      await tester.tap(find.byKey(const Key('suggestion_not_now')));
      await tester.pumpAndSettle();
      expect(find.text('Make the buttons bigger?'), findsNothing);
      expect(accessibility.settings.buttonScale, 1.0);
    });

    testWidgets('opt-out hides the card for good', (tester) async {
      await showSuggestion(tester);
      await tester.tap(find.byKey(const Key('suggestion_opt_out')));
      await tester.pumpAndSettle();
      expect(find.text('Make the buttons bigger?'), findsNothing);
      expect(manager.optedOut, {'near-miss-buttons'});
    });
  });
}
