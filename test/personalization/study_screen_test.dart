// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/meaning/meaning_settings.dart';
import 'package:fluffychat/personalization/study/study_events.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_screen.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStorage implements StudyLogStorage {
  final List<String> lines = [];

  @override
  Future<void> append(String line) async => lines.add(line);

  @override
  Future<List<String>> readLines() async => [...lines];

  @override
  Future<void> clear() async => lines.clear();
}

void main() {
  late SharedPreferences store;
  late StudySettings settings;
  late MemoryStorage storage;
  late StudyLog log;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'FluffyChat',
      packageName: 'chat.fluffy.fluffychat',
      version: '2.6.0',
      buildNumber: '42',
      buildSignature: '',
    );
    store = await SharedPreferences.getInstance();
    settings = StudySettings(store);
    StudySettings.instance = settings;
    MeaningSettings.instance = MeaningSettings(store);
    storage = MemoryStorage();
  });

  tearDown(() => StudyLog.instance = null);

  // Made in the test body, so the log's writes run in the test's fake async
  // zone.
  void startLog() {
    log = StudyLog(settings: settings, storage: storage);
    StudyLog.instance = log;
  }

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: home,
  );

  List<String> types() => [
    for (final line in storage.lines) jsonDecode(line)['type'] as String,
  ];

  testWidgets('changing the condition asks first', (tester) async {
    startLog();
    await settings.update(settings.value.copyWith(logging: true));
    await tester.pumpWidget(app(const StudyScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('study_condition_manual_only')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.value.condition, StudyCondition.assist);
    expect(storage.lines, isEmpty);

    await tester.tap(find.byKey(const Key('study_condition_manual_only')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('study_confirm')));
    await tester.pumpAndSettle();
    expect(settings.value.condition, StudyCondition.manualOnly);
    expect(types(), ['condition_changed']);
    expect(jsonDecode(storage.lines.single), containsPair('to', 'manual_only'));
  });

  testWidgets('logging starts only when the researcher turns it on', (
    tester,
  ) async {
    startLog();
    await tester.pumpWidget(app(const StudyScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Nothing recorded yet.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('study_save'))).enabled,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('study_logging')));
    await tester.pumpAndSettle();
    expect(settings.value.logging, isTrue);
    expect(types(), ['logging_started']);
    expect(find.text('1 event recorded'), findsOneWidget);
    expect(find.textContaining('"logging_started"'), findsOneWidget);

    await tester.tap(find.byKey(const Key('study_logging')));
    await tester.pumpAndSettle();
    expect(settings.value.logging, isFalse);
    expect(types(), ['logging_started', 'logging_stopped']);
    log.record(const AssistPrompted('not recorded'));
    await log.flushed;
    expect(storage.lines, hasLength(2));
  });

  testWidgets('saving exports a header and every event', (tester) async {
    startLog();
    await settings.update(settings.value.copyWith(logging: true));
    log.record(const LoggingStarted(StudyCondition.assist));
    log.record(const AssistPrompted('the text is tiny'));
    String? savedName;
    Uint8List? savedBytes;
    await tester.pumpWidget(
      app(
        StudyScreen(
          save: (name, bytes) async {
            savedName = name;
            savedBytes = bytes;
            return '/storage/$name';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('study_participant')), 'P 07');
    await tester.pumpAndSettle();
    expect(settings.value.participant, 'P 07');

    await tester.ensureVisible(find.byKey(const Key('study_save')));
    await tester.tap(find.byKey(const Key('study_save')));
    await tester.pumpAndSettle();

    expect(savedName, startsWith('study-log-P_07-'));
    expect(savedName, endsWith('.jsonl'));
    final lines = const LineSplitter().convert(utf8.decode(savedBytes!));
    final header = jsonDecode(lines.first) as Map<String, Object?>;
    expect(header['type'], 'header');
    expect(header['participant'], 'P 07');
    expect(header['condition'], 'assist');
    expect(header['app_version'], '2.6.0+42');
    expect(
      [for (final l in lines.skip(1)) jsonDecode(l)['type']],
      ['logging_started', 'assist_prompt'],
    );
    expect(types().last, 'log_exported');
    expect(find.textContaining('/storage/study-log-P_07-'), findsOneWidget);
  });

  group('clearing', () {
    late List<String> saved;

    Future<void> pumpWithEvents(WidgetTester tester) async {
      startLog();
      await settings.update(
        settings.value.copyWith(logging: true, participant: 'P01'),
      );
      log.record(const LoggingStarted(StudyCondition.assist));
      log.record(const AssistPrompted('my eyes are bad'));
      saved = [];
      await tester.pumpWidget(
        app(
          StudyScreen(
            save: (name, bytes) async {
              saved.add(utf8.decode(bytes));
              return '/storage/$name';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapAction(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('save and clear clears only after the file is saved', (
      tester,
    ) async {
      await pumpWithEvents(tester);
      await tapAction(tester, 'study_save_and_clear');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(storage.lines, hasLength(2));

      await tapAction(tester, 'study_save_and_clear');
      await tester.tap(find.byKey(const Key('study_confirm')));
      await tester.pumpAndSettle();
      expect(saved.single, contains('my eyes are bad'));
      expect(storage.lines, hasLength(1));
      final cleared = jsonDecode(storage.lines.single) as Map<String, Object?>;
      expect(cleared['type'], 'log_cleared');
      expect(cleared['events'], 2);
      expect(cleared['saved'], true);
    });

    testWidgets('a cancelled save keeps the log', (tester) async {
      startLog();
      await settings.update(settings.value.copyWith(logging: true));
      log.record(const AssistPrompted('keep me'));
      await tester.pumpWidget(
        app(StudyScreen(save: (name, bytes) async => null)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('study_save_and_clear')));
      await tester.tap(find.byKey(const Key('study_save_and_clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('study_confirm')));
      await tester.pumpAndSettle();
      expect(types(), ['assist_prompt']);
    });

    testWidgets('delete removes the log without saving it', (tester) async {
      await pumpWithEvents(tester);
      await tapAction(tester, 'study_delete');
      await tester.tap(find.byKey(const Key('study_confirm')));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(types(), ['log_cleared']);
      expect(jsonDecode(storage.lines.single)['saved'], false);
      expect(storage.lines.join(), isNot(contains('my eyes are bad')));
      expect(find.text('The log was cleared.'), findsOneWidget);
    });
  });

  testWidgets('holding the entry for three seconds opens the screen', (
    tester,
  ) async {
    startLog();
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: Center(child: StudyEntry(child: Text('Accessibility'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> hold(Duration duration) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Accessibility')),
      );
      await tester.pump(duration);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await hold(const Duration(seconds: 1));
    expect(find.byType(StudyScreen), findsNothing);

    await hold(const Duration(seconds: 3));
    expect(find.byType(StudyScreen), findsOneWidget);
  });
}
