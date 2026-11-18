// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

/// Opens a chat at every screen width and at the extremes of the size
/// settings, with and without button labels, and fails on any overflow.
void main() {
  late Client client;
  late Room room;

  setUpAll(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
    room = client.rooms.firstWhere(
      (r) => r.membership == Membership.join && !r.isSpace && r.encrypted,
    );
  });

  const buttons = [
    ScaleCategory.sendButton,
    ScaleCategory.attachButton,
    ScaleCategory.emojiButton,
    ScaleCategory.microphoneButton,
    ScaleCategory.backButton,
    ScaleCategory.menuButton,
  ];
  final presets = <String, Map<ScaleCategory, double>>{
    'defaults': {},
    'all min': {for (final c in ScaleCategory.values) c: c.min},
    'all max': {for (final c in ScaleCategory.values) c: c.max},
    'big buttons, small text': {
      ScaleCategory.button: 2.0,
      ScaleCategory.touchTarget: 2.0,
      for (final c in buttons) c: c.max,
      ScaleCategory.text: 0.8,
    },
    'big text, small buttons': {
      ScaleCategory.text: 2.0,
      for (final c in buttons) c: c.min,
    },
  };
  const widths = [320.0, 360.0, 412.0, 600.0];
  const systemTextScales = [1.0, 2.0];

  for (final labels in [false, true]) {
    for (final MapEntry(key: name, value: values) in presets.entries) {
      testWidgets('chat fits: $name, labels $labels', (tester) async {
        for (final width in widths) {
          for (final systemText in systemTextScales) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            final controller = AccessibilityController(prefs);
            await controller.setToggle(
              AccessibilityToggle.buttonLabels,
              labels,
            );
            for (final MapEntry(:key, :value) in values.entries) {
              await controller.apply(key, value);
            }
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = systemText;

            await tester.pumpWidget(
              AccessibilityScope(
                controller: controller,
                child: FluffyChatApp(
                  clients: [client],
                  store: prefs,
                  appLockSettings: (pincode: null, useBiometrics: false),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 100));
            FluffyChatApp.router.go('/rooms/${room.id}');
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pump(const Duration(milliseconds: 500));

            final where = '$width wide, system text $systemText';
            expect(find.byType(ChatInputRow), findsOneWidget, reason: where);
            expect(tester.takeException(), isNull, reason: where);
            // The timeline pads its last message by the input bar's height.
            final chat = tester.state<ChatController>(
              find.byType(ChatPageWithRoom),
            );
            expect(
              chat.inputBarHeight,
              equals(
                tester
                    .getSize(
                      find.ancestor(
                        of: find.byType(ChatInputRow),
                        matching: find.byType(SizeChangedLayoutNotifier),
                      ),
                    )
                    .height,
              ),
              reason: where,
            );
            if (labels &&
                name == 'defaults' &&
                width >= 412 &&
                systemText == 1) {
              // With room to spare, labels show at full size, not cut or shrunk.
              final labelTexts = find.descendant(
                of: find.byType(ChatInputRow),
                matching: find.descendant(
                  of: find.byType(AccessibilityButtonLabel),
                  matching: find.byType(Text),
                ),
              );
              expect(labelTexts, findsWidgets, reason: where);
              for (final element in labelTexts.evaluate()) {
                final paragraph = element.renderObject! as RenderParagraph;
                final shown =
                    tester.getBottomRight(find.byWidget(element.widget)).dx -
                    tester.getTopLeft(find.byWidget(element.widget)).dx;
                expect(
                  shown,
                  paragraph.getMaxIntrinsicWidth(double.infinity),
                  reason: where,
                );
              }
            }

            // The input row reads the selection through the timeline, which
            // does not load from the database under the test clock.
            chat.timeline ??= Timeline(
              room: room,
              chunk: TimelineChunk(events: []),
            );
            // Selecting one of our own messages fills the top bar with every
            // action at once: close, edit, thread, copy, delete and more.
            chat.onSelectMessage(
              Event(
                content: {'msgtype': 'm.text', 'body': 'Hi'},
                type: EventTypes.Message,
                eventId: '\$selected',
                senderId: client.userID!,
                originServerTs: DateTime.now(),
                room: room,
              ),
            );
            await tester.pump();
            expect(chat.canEditSelectedEvents, isTrue, reason: where);
            expect(chat.canRedactSelectedEvents, isTrue, reason: where);
            // Actions that do not fit move into the "more" menu.
            final more = find.descendant(
              of: find.byType(AppBar),
              matching: find.byIcon(Icons.adaptive.more),
            );
            if (find.byIcon(Icons.delete_outlined).evaluate().isEmpty) {
              await tester.tap(more);
              await tester.pump(const Duration(milliseconds: 500));
              expect(
                find.byIcon(Icons.delete_outlined),
                findsOneWidget,
                reason: '$where, in the menu',
              );
              await tester.tapAt(Offset.zero);
              await tester.pump(const Duration(milliseconds: 500));
            }
            expect(tester.takeException(), isNull, reason: '$where, selected');
            chat.clearSelectedEvents();

            await tester.pumpWidget(const SizedBox());
            // Lets the chat's network and database timers finish.
            await tester.pump(const Duration(seconds: 31));
            controller.dispose();
          }
        }
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
      });
    }
  }
}
