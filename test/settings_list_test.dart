// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/settings_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, TargetPlatform platform) =>
      tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const Material(
            child: SettingsList(
              children: [
                ListTile(title: Text('a')),
                Divider(),
                SettingsHeader('Header'),
                ListTile(title: Text('b')),
                ListTile(title: Text('c')),
              ],
            ),
          ),
        ),
      );

  testWidgets('iOS starts a card at every header and divider', (tester) async {
    await pump(tester, TargetPlatform.iOS);
    expect(find.byType(SettingsSection), findsNWidgets(2));
    expect(find.text('Header'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
  });

  testWidgets('Material keeps the plain list', (tester) async {
    await pump(tester, TargetPlatform.android);
    expect(find.byType(SettingsSection), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    // The header is a tile in the secondary color.
    expect(find.byType(ListTile), findsNWidgets(4));
  });
}
