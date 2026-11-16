// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/meaning/meaning_rules.dart';
import 'package:fluffychat/personalization/meaning/message_meaning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tuesday 27 October 2026, 18:00.
  final now = DateTime(2026, 10, 27, 18);
  const ns = MessageMeaning.namespace;

  group('MessageMeaning', () {
    const meaning = MessageMeaning(
      intent: MessageIntent.question,
      urgency: MessageUrgency.high,
      times: [MeaningTime('kl. 10', at: '2026-10-28T10:00')],
    );

    test('uses the agreed namespace', () {
      expect(ns, 'dk.aau.sw9.meaning');
    });

    test('round trip through message content', () {
      final content = {'body': 'x', ns: meaning.toJson()};
      expect(MessageMeaning.fromContent(content), meaning);
      expect(meaning.toJson()['v'], 1);
    });

    test('missing, unknown version or invalid meaning gives null', () {
      for (final raw in <Object?>[
        null,
        'question',
        {'v': 2, 'intent': 'question'},
        {'intent': 'question'},
        {'v': 1, 'intent': 'shout'},
        {'v': 1, 'intent': 'question', 'urgency': 'extreme'},
        {'v': 1, 'intent': 'question', 'times': 'tomorrow'},
        {
          'v': 1,
          'intent': 'question',
          'times': [
            {'at': '2026-10-28'},
          ],
        },
        {
          'v': 1,
          'intent': 'question',
          'times': [
            {'text': 'soon', 'at': 'not a date'},
          ],
        },
      ]) {
        expect(
          MessageMeaning.fromContent({'body': 'x', ns: ?raw}),
          isNull,
          reason: '$raw',
        );
      }
    });

    test('urgency and times are optional', () {
      expect(
        MessageMeaning.fromContent({
          ns: {'v': 1, 'intent': 'request'},
        }),
        const MessageMeaning(intent: MessageIntent.request),
      );
    });
  });

  group('MeaningRules intent', () {
    for (final (text, intent) in [
      ('Are we still meeting tomorrow?', MessageIntent.question),
      ('how are you', MessageIntent.question),
      ('Hvornår kommer du', MessageIntent.question),
      ('Ses vi i morgen?', MessageIntent.question),
      ('Please call me', MessageIntent.request),
      ('Can you buy milk?', MessageIntent.request),
      ('Husk at tage medicin', MessageIntent.request),
      ('Kan du ringe til mig?', MessageIntent.request),
      ('I am home now', MessageIntent.information),
      ('Jeg er hjemme', MessageIntent.information),
      ('', MessageIntent.information),
    ]) {
      test('"$text" is ${intent.name}', () {
        expect(MeaningRules.intentOf(text), intent);
      });
    }
  });

  group('MeaningRules urgency', () {
    for (final (text, urgency) in [
      ('Call me, it is urgent', MessageUrgency.high),
      ('Det haster!', MessageUrgency.high),
      ('Come now!!', MessageUrgency.high),
      ('See you later', MessageUrgency.normal),
    ]) {
      test('"$text" is ${urgency.name}', () {
        expect(MeaningRules.urgencyOf(text), urgency);
      });
    }
  });

  group('MeaningRules times', () {
    for (final (text, expected) in [
      (
        'Shall we meet tomorrow at 10?',
        [('tomorrow at 10', '2026-10-28T10:00')],
      ),
      ('Ses vi i morgen kl. 14?', [('i morgen kl. 14', '2026-10-28T14:00')]),
      ('Dinner at 7pm', [('at 7pm', '2026-10-27T19:00')]),
      ('Lægen kl. 9.30', [('kl. 9.30', '2026-10-27T09:30')]),
      ('The bus leaves at 10:45', [('at 10:45', '2026-10-27T10:45')]),
      ('See you on Friday', [('on Friday', '2026-10-30')]),
      ('Vi ses på mandag', [('på mandag', '2026-11-02')]),
      ('See you next Tuesday', [('next Tuesday', '2026-11-03')]),
      ('It costs 3.50', <(String, String)>[]),
      ('I am 85 years old', <(String, String)>[]),
      (
        'Today at 9 and Thursday kl 16',
        [
          ('Today at 9', '2026-10-27T09:00'),
          ('Thursday kl 16', '2026-10-29T16:00'),
        ],
      ),
    ]) {
      test('"$text"', () {
        expect([
          for (final t in MeaningRules.timesIn(text, now)) (t.text, t.at),
        ], expected);
      });
    }
  });
}
