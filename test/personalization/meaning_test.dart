// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/meaning/annotated_send.dart';
import 'package:fluffychat/personalization/meaning/meaning_draft.dart';
import 'package:fluffychat/personalization/meaning/meaning_rules.dart';
import 'package:fluffychat/personalization/meaning/meaning_settings.dart';
import 'package:fluffychat/personalization/meaning/message_meaning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      ('Ses i morgen', MessageIntent.information),
      ('Have a nice day', MessageIntent.information),
      ('Will do', MessageIntent.information),
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
      ('Ses vi i morgen kl. 14?', [('i morgen kl. 14', '2026-10-28T14:00')]),
      ('Dinner at 7pm', [('at 7pm', '2026-10-27T19:00')]),
      ('The train leaves at 15:30', [('at 15:30', '2026-10-27T15:30')]),
      ('See you on Friday', [('on Friday', '2026-10-30')]),
      ('Vi ses på mandag', [('på mandag', '2026-11-02')]),
      ('See you next Tuesday', [('next Tuesday', '2026-11-03')]),
      ('It costs 3.50', <(String, String?)>[]),
      ('I am 85 years old', <(String, String?)>[]),
      // "at" without minutes or am/pm is not a time.
      ('Come at 3', <(String, String?)>[]),
      ('Det er godt at 2 af os kommer', <(String, String?)>[]),
      ('Shall we meet tomorrow at 10?', [('tomorrow', '2026-10-28')]),
      // Hours 1 to 12 without am/pm keep only the sender's words; a named
      // day is still resolved.
      ('Lægen kl. 9.30', [('kl. 9.30', null)]),
      ('The bus leaves at 10:45', [('at 10:45', null)]),
      ('Vi kommer i morgen kl. 3', [('i morgen kl. 3', '2026-10-28')]),
      (
        'Today at 9 and Thursday kl 16',
        [('Today', '2026-10-27'), ('Thursday kl 16', '2026-10-29T16:00')],
      ),
    ]) {
      test('"$text"', () {
        expect([
          for (final t in MeaningRules.timesIn(text, now)) (t.text, t.at),
        ], expected);
      });
    }
  });

  group('MeaningDraft', () {
    late TextEditingController text;
    late MeaningSettings settings;
    late MeaningDraft draft;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = MeaningSettings(await SharedPreferences.getInstance());
      text = TextEditingController();
      draft = MeaningDraft(text, settings: settings, clock: () => now);
    });

    tearDown(() {
      draft.dispose();
      text.dispose();
    });

    test('nothing while the input is empty', () {
      expect(draft.meaning, isNull);
    });

    test('follows the text', () {
      text.text = 'Ses vi i morgen kl. 14?';
      expect(draft.meaning!.intent, MessageIntent.question);
      expect(draft.meaning!.times.single.text, 'i morgen kl. 14');
    });

    test('the sender can change and remove parts', () {
      text.text = 'Ses vi i morgen kl. 14?';
      draft.setIntent(MessageIntent.request);
      draft.setUrgency(MessageUrgency.high);
      draft.removeTime(draft.meaning!.times.single);
      expect(
        draft.meaning,
        const MessageMeaning(
          intent: MessageIntent.request,
          urgency: MessageUrgency.high,
        ),
      );
    });

    test('the sender can send without meaning', () {
      text.text = 'Hello?';
      draft.remove();
      expect(draft.meaning, isNull);
      expect(draft.take(), isNull);
    });

    test('take resets the draft for the next message', () {
      text.text = 'Hello?';
      draft.setIntent(MessageIntent.information);
      expect(draft.take()!.intent, MessageIntent.information);
      text.text = 'Next?';
      expect(draft.meaning!.intent, MessageIntent.question);
    });

    test('nothing when turned off in the settings', () async {
      await settings.update(const MeaningPreferences(annotateOutgoing: false));
      text.text = 'Hello?';
      expect(draft.meaning, isNull);
    });
  });

  group('buildAnnotatedTextContent', () {
    late Client client;
    late Room room;

    setUpAll(() async {
      sqfliteFfiInit();
      client = Client(
        'meaning test',
        database: await MatrixSdkDatabase.init(
          'meaning-test',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
      room = Room(id: '!room:example.org', client: client);
    });

    test('puts the meaning next to body, not in relations', () {
      const meaning = MessageMeaning(intent: MessageIntent.question);
      final content = buildAnnotatedTextContent(
        room,
        'Are you coming?',
        meaning: meaning,
      );
      expect(content['msgtype'], MessageTypes.Text);
      expect(content['body'], 'Are you coming?');
      expect(content[ns], meaning.toJson());
      expect(content.containsKey('m.relates_to'), isFalse);
    });

    test('keeps formatting like the SDK', () {
      final content = buildAnnotatedTextContent(room, '**bold**');
      expect(content['format'], 'org.matrix.custom.html');
      expect(content['formatted_body'], contains('<strong>bold</strong>'));
      expect(content.containsKey(ns), isFalse);
    });

    test('plain text gets no formatted body', () {
      final content = buildAnnotatedTextContent(room, 'just text');
      expect(content.containsKey('formatted_body'), isFalse);
    });
  });
}
