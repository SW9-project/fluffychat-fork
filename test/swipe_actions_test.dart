// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/swipe_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester) async {
    final pressed = <String>[];
    SwipeAction action(String label) => SwipeAction(
      label: label,
      icon: Icons.circle,
      color: Colors.blue,
      onPressed: () => pressed.add(label),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeActions(
            leading: [action('Pin')],
            trailing: [action('More'), action('Leave')],
            child: ListTile(
              title: const Text('chat'),
              onTap: () => pressed.add('open'),
            ),
          ),
        ),
      ),
    );
    return pressed;
  }

  testWidgets('Swiping reveals the actions of that side', (tester) async {
    final pressed = await pump(tester);
    await tester.drag(find.text('chat'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('Pin'), findsNothing);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(pressed, ['Leave']);
    expect(find.text('Leave'), findsNothing);

    await tester.drag(find.text('chat'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.text('More'), findsNothing);
    await tester.tap(find.text('Pin'));
    expect(pressed, ['Leave', 'Pin']);
  });

  testWidgets('Short swipes snap back, taps close an open row', (
    tester,
  ) async {
    final pressed = await pump(tester);
    await tester.drag(find.text('chat'), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(find.text('More'), findsNothing);

    await tester.drag(find.text('chat'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    // The row above the chat takes the tap.
    await tester.tap(find.text('chat'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('More'), findsNothing);
    expect(pressed, isEmpty);

    await tester.tap(find.text('chat'));
    expect(pressed, ['open']);
  });
}
