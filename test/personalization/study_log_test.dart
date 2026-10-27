// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/meaning/annotated_send.dart';
import 'package:fluffychat/personalization/meaning/meaning_draft.dart';
import 'package:fluffychat/personalization/meaning/meaning_settings.dart';
import 'package:fluffychat/personalization/meaning/message_meaning.dart';
import 'package:fluffychat/personalization/study/study_events.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStorage implements StudyLogStorage {
  final List<String> lines = [];

  @override
  Future<void> append(String line) async => lines.add(line);

  @override
  Future<List<String>> readLines() async => [...lines];
}

class FakeClient extends Fake implements Client {
  @override
  String? get userID => '@alice:example.org';

  @override
  bool get convertLinebreaksInFormatting => true;

  @override
  bool get enableLatexMarkdown => false;
}

class FakeRoom extends Fake implements Room {
  final List<Map<String, dynamic>> sent = [];

  @override
  final Client client = FakeClient();

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    sent.add(content);
    return '\$event${sent.length}';
  }
}

void main() {
  late SharedPreferences store;
  late StudySettings settings;
  late MemoryStorage storage;
  late StudyLog log;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    settings = StudySettings(store);
    storage = MemoryStorage();
    log = StudyLog(
      settings: settings,
      storage: storage,
      clock: () => DateTime.utc(2026, 10, 27, 9, 30),
    );
  });

  tearDown(() => StudyLog.instance = null);

  Future<void> turnOn() =>
      settings.update(settings.value.copyWith(logging: true));

  List<Map<String, Object?>> decoded(List<String> lines) => [
    for (final line in lines) jsonDecode(line) as Map<String, Object?>,
  ];

  group('StudySettings', () {
    test('logging is off and the condition is Assist by default', () {
      expect(settings.value.logging, isFalse);
      expect(settings.value.condition, StudyCondition.assist);
      expect(settings.value.participant, '');
    });

    test('values survive a restart', () async {
      await settings.update(
        const StudyPreferences(
          condition: StudyCondition.manualOnly,
          logging: true,
          participant: 'P07',
        ),
      );
      final again = StudySettings(store);
      expect(again.value.condition, StudyCondition.manualOnly);
      expect(again.value.logging, isTrue);
      expect(again.value.participant, 'P07');
    });

    test('an unknown stored condition falls back to Assist', () async {
      await store.setString('personalization.study.condition', 'other');
      expect(StudySettings(store).value.condition, StudyCondition.assist);
    });
  });

  group('StudyLog', () {
    test('records nothing while logging is off', () async {
      log.record(const AssistPrompted('hello'));
      log.record(const LoggingStopped());
      await log.flushed;
      expect(storage.lines, isEmpty);
    });

    test('records events in order with a UTC timestamp', () async {
      await turnOn();
      log.record(const LoggingStarted(StudyCondition.assist));
      log.record(const AssistPrompted('the buttons are too small'));
      log.record(const LogExported(2));
      final events = decoded(await log.lines());
      expect(
        [for (final e in events) e['type']],
        ['logging_started', 'assist_prompt', 'log_exported'],
      );
      expect(events.first['t'], '2026-10-27T09:30:00.000Z');
      expect(events.first['condition'], 'assist');
      expect(events[1]['prompt'], 'the buttons are too small');
      expect(events[2]['events'], 2);
    });

    test('the app-wide log records nothing before it starts', () async {
      StudyLog.instance.record(const AssistPrompted('hello'));
      expect(StudyLog.instance.isRecording, isFalse);
      expect(await StudyLog.instance.lines(), isEmpty);
    });

    test('an export starts with a header line', () async {
      await turnOn();
      log.record(const LoggingStarted(StudyCondition.manualOnly));
      final text = utf8.decode(await log.export({'participant': 'P01'}));
      final lines = const LineSplitter().convert(text);
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first), {'type': 'header', 'participant': 'P01'});
      expect(jsonDecode(lines.last)['type'], 'logging_started');
    });

    test('the file keeps earlier events after a restart', () async {
      final directory = await Directory.systemTemp.createTemp('study_log');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/nested/study_log.jsonl');
      await turnOn();

      final first = StudyLog(
        settings: settings,
        storage: FileStudyLogStorage(() async => file),
      );
      first.record(const LoggingStarted(StudyCondition.assist));
      first.record(const AssistPrompted('one'));
      await first.flushed;

      final second = StudyLog(
        settings: settings,
        storage: FileStudyLogStorage(() async => file),
      );
      second.record(const AssistPrompted('two'));
      final events = decoded(await second.lines());
      expect(
        [for (final e in events) e['prompt'] ?? e['type']],
        ['logging_started', 'one', 'two'],
      );
    });
  });

  group('events', () {
    test('settings changes record each changed value', () async {
      await turnOn();
      final controller = AccessibilityController(store);
      addTearDown(controller.dispose);
      controller.commits.listen((c) => log.record(SettingsChanged(c)));

      await controller.apply(ScaleCategory.text, 1.5);
      controller.beginEdit();
      controller.preview(ScaleCategory.button, 1.3);
      controller.preview(ScaleCategory.button, 1.6);
      await controller.endEdit();
      await controller.undo();
      await controller.reset();
      await Future<void>.delayed(Duration.zero);

      final events = decoded(await log.lines());
      expect(
        [for (final e in events) e['kind']],
        ['apply', 'edit', 'undo', 'reset'],
      );
      expect(events[0]['changes'], {
        'text_scale': [1.0, 1.5],
        'input_text_scale': [1.0, 1.5],
      });
      expect(events[1]['changes'], {
        'button_scale': [1.0, 1.6],
      });
      expect(events[2]['changes'], {
        'button_scale': [1.6, 1.0],
      });
      expect(events[3]['changes'], {
        'text_scale': [1.5, 1.0],
        'input_text_scale': [1.5, 1.0],
      });
    });

    test('meaning events never contain message text', () async {
      await turnOn();
      StudyLog.instance = log;
      final meaningSettings = MeaningSettings(store);
      final text = TextEditingController(
        text: 'SECRET Ses vi i morgen kl. 14?',
      );
      final draft = MeaningDraft(
        text,
        settings: meaningSettings,
        clock: () => DateTime(2026, 10, 27, 9),
      );
      addTearDown(draft.dispose);

      draft.setUrgency(MessageUrgency.high);
      draft.setIntent(MessageIntent.request);
      final room = FakeRoom();
      await sendAnnotatedText(room, text.text, meaning: draft.take());
      expect(
        room.sent.single[MessageMeaning.namespace],
        containsPair('intent', 'request'),
      );

      text.text = 'SECRET Kan du ringe på fredag kl. 10?';
      draft.removeTime(draft.meaning!.times.single);
      await sendAnnotatedText(
        room,
        text.text,
        meaning: draft.take(),
        editEventId: r'$event1',
      );
      text.text = 'SECRET without meaning';
      draft.remove();
      expect(draft.take(), isNull);
      await meaningSettings.update(
        meaningSettings.value.copyWith(highlightTimes: false),
      );

      final exported = utf8.decode(await log.export(const {}));
      for (final secret in [
        'SECRET',
        'Ses vi',
        'morgen',
        'kl. 14',
        'fredag',
        'kl. 10',
        '2026-10-28',
      ]) {
        expect(exported, isNot(contains(secret)));
      }
      final events = decoded(await log.lines());
      expect(
        [for (final e in events) e['type']],
        [
          'meaning_changed',
          'meaning_changed',
          'meaning_sent',
          'meaning_changed',
          'meaning_sent',
          'meaning_removed',
          'meaning_settings',
        ],
      );
      expect(events[2], containsPair('times', 1));
      expect(events[2], containsPair('edit', false));
      expect(events[3], containsPair('time_removed', true));
      expect(events[4], containsPair('times', 0));
      expect(events[4], containsPair('edit', true));
      expect(events[6], containsPair('highlight_times', false));
    });
  });
}
