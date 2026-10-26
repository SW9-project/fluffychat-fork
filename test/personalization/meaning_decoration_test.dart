// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/meaning/meaning_decoration.dart';
import 'package:fluffychat/personalization/meaning/meaning_settings.dart';
import 'package:fluffychat/personalization/meaning/message_meaning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MeaningSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = MeaningSettings(await SharedPreferences.getInstance());
    MeaningSettings.instance = settings;
  });

  Future<void> pump(WidgetTester tester, Map<String, Object?> content) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeaningDecoration(
              content: content,
              textColor: Colors.black,
              child: Text(content['body'] as String),
            ),
          ),
        ),
      );

  final annotated = {
    'body': 'Ses vi i morgen kl. 14?',
    MessageMeaning.namespace: const MessageMeaning(
      intent: MessageIntent.question,
      urgency: MessageUrgency.high,
      times: [MeaningTime('i morgen kl. 14', at: '2026-10-28T14:00')],
    ).toJson(),
  };

  testWidgets('shows markers and times around the original text', (
    tester,
  ) async {
    await pump(tester, annotated);
    expect(find.text('Ses vi i morgen kl. 14?'), findsOneWidget);
    expect(find.byKey(const Key('meaning_badge_intent')), findsOneWidget);
    expect(find.text('Question'), findsOneWidget);
    expect(find.byKey(const Key('meaning_badge_urgent')), findsOneWidget);
    expect(find.byKey(const Key('meaning_time')), findsOneWidget);
    expect(find.textContaining('i morgen kl. 14 ·'), findsOneWidget);
  });

  testWidgets('follows the receiver settings', (tester) async {
    await settings.update(
      const MeaningPreferences(
        showIntent: false,
        showUrgency: false,
        highlightTimes: false,
      ),
    );
    await pump(tester, annotated);
    expect(find.text('Ses vi i morgen kl. 14?'), findsOneWidget);
    expect(find.byKey(const Key('meaning_badge_intent')), findsNothing);
    expect(find.byKey(const Key('meaning_badge_urgent')), findsNothing);
    expect(find.byKey(const Key('meaning_time')), findsNothing);
  });

  for (final (label, content) in [
    ('no meaning', {'body': 'Hello'}),
    (
      'an unknown version',
      {
        'body': 'Hello',
        MessageMeaning.namespace: {'v': 99, 'intent': 'question'},
      },
    ),
    (
      'invalid meaning',
      {
        'body': 'Hello',
        MessageMeaning.namespace: {'v': 1, 'intent': 42},
      },
    ),
  ]) {
    testWidgets('$label shows the plain text only', (tester) async {
      await pump(tester, content);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.byKey(const Key('meaning_badge_intent')), findsNothing);
      expect(find.byKey(const Key('meaning_time')), findsNothing);
    });
  }
}
