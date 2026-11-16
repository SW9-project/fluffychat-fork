// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/html_message.dart';
import 'package:fluffychat/personalization/simplified_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {}

void main() {
  testWidgets(
    'calmer message layout follows mode without losing personal text scaling',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      final store = await AppSettings.init(loadWebConfigFile: false);
      debugDefaultTargetPlatformOverride = null;
      final controller = SimplifiedInterfaceController(store);
      final room = Room(id: '!example:test', client: _Client());
      await tester.pumpWidget(
        MaterialApp(
          home: SimplifiedInterfaceScope(
            controller: controller,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: Scaffold(
                body: HtmlMessage(
                  html: '<p>Hello there.</p>',
                  room: room,
                  fontSize: 14,
                  linkStyle: const TextStyle(),
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final message = find
          .descendant(of: find.byType(HtmlMessage), matching: find.byType(Text))
          .first;
      expect(tester.widget<Text>(message).style?.height, null);
      final normalHeight = tester.getSize(message).height;
      controller.setEnabled(true);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(message).style?.height, 1.5);
      expect(tester.getSize(message).height, greaterThan(normalHeight));
      expect(
        MediaQuery.textScalerOf(tester.element(message)).scale(14),
        closeTo(25.2, .01),
      );
      controller.setEnabled(false);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(message).style?.height, null);
      expect(tester.getSize(message).height, normalHeight);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
