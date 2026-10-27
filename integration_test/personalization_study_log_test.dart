// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Phase 5 check on a device: the study log writes to the app's private
// storage, and a saved export keeps what was typed in the Assist tab but no
// message text. A stand-in model answers (FunctionGemma does not run on the
// x86_64 emulator) and a stand-in room takes the messages, so no homeserver
// is needed.
//
// Run as a separate app, like the model harness, so the installed app keeps
// its data:
//   flutter test integration_test/personalization_study_log_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/meaning/annotated_send.dart';
import 'package:fluffychat/personalization/meaning/meaning_draft.dart';
import 'package:fluffychat/personalization/meaning/meaning_settings.dart';
import 'package:fluffychat/personalization/meaning/message_meaning.dart';
import 'package:fluffychat/personalization/model/settings_functions.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_screen.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: avoid_print
void report(String line) => print('[study] $line');

class _Model implements SettingsIntentModel {
  @override
  final ValueListenable<ModelStatus> status = ValueNotifier(
    const ModelStatus(ModelState.ready),
  );

  @override
  ModelTiming? lastTiming;

  @override
  Future<void> prepare() async {}

  @override
  Future<ProposedCall?> propose(
    String text,
    List<FunctionDeclaration> functions,
  ) async {
    lastTiming = const ModelTiming(totalMs: 1);
    return const ProposedCall('heuristic_near_miss_buttons', {'steps': 1});
  }

  @override
  Future<void> release() async {}

  @override
  void dispose() {}
}

class _Client extends Fake implements Client {
  @override
  String? get userID => '@alice:example.org';

  @override
  bool get convertLinebreaksInFormatting => true;

  @override
  bool get enableLatexMarkdown => false;
}

class _Room extends Fake implements Room {
  @override
  final Client client = _Client();

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
  }) async => r'$event';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a saved study log has no message text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    final settings = StudySettings(store);
    await settings.update(
      settings.value.copyWith(logging: true, participant: 'TEST'),
    );
    final directory = await getApplicationSupportDirectory();
    final file = File(
      '${directory.path}/personalization/study_log_check.jsonl',
    );
    if (await file.exists()) await file.delete();
    final log = StudyLog(
      settings: settings,
      storage: FileStudyLogStorage(() async => file),
    );
    StudyLog.instance = log;
    report('log file ${file.path}');

    // The Assist tab: a prompt, a proposal, Apply.
    final accessibility = AccessibilityController(store);
    final manager = SuggestionManager(
      accessibility: accessibility,
      store: store,
      config: HeuristicsConfig.fromJson(
        jsonDecode(
              await rootBundle.loadString(PersonalizationLayer.heuristicsAsset),
            )
            as Map<String, Object?>,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: AssistView(
            model: _Model(),
            manager: manager,
            accessibility: accessibility,
            onOpenAccessibilitySettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const prompt = 'The buttons are too small for me';
    await tester.enterText(find.byKey(const Key('assist_input')), prompt);
    await tester.tap(find.byKey(const Key('assist_send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assist_apply')));
    await tester.pumpAndSettle();
    manager.dismissApplied();

    // Two messages with meaning, one without.
    const messages = [
      'SECRET-1 Ses vi i morgen kl. 14?',
      'SECRET-2 Kan du ringe på fredag kl. 10?',
      'SECRET-3 no meaning',
    ];
    final text = TextEditingController();
    final draft = MeaningDraft(text, settings: MeaningSettings(store));
    final room = _Room();
    text.text = messages[0];
    draft.setUrgency(MessageUrgency.high);
    await sendAnnotatedText(room, text.text, meaning: draft.take());
    text.text = messages[1];
    draft.removeTime(draft.meaning!.times.single);
    await sendAnnotatedText(room, text.text, meaning: draft.take());
    text.text = messages[2];
    draft.remove();
    expect(draft.take(), isNull);
    await log.flushed;

    // The researcher saves the log from the study screen.
    Uint8List? saved;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: StudyScreen(
          settings: settings,
          log: log,
          save: (name, bytes) async {
            saved = bytes;
            final copy = File('${directory.path}/personalization/$name');
            await copy.writeAsBytes(bytes);
            return copy.path;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('study_save')));
    await tester.tap(find.byKey(const Key('study_save')));
    await tester.pumpAndSettle();

    final exported = utf8.decode(saved!);
    for (final line in const LineSplitter().convert(exported)) {
      report(line);
    }
    expect(exported, contains(prompt));
    for (final secret in [
      'SECRET',
      'Ses vi',
      'morgen',
      'kl. 14',
      'fredag',
      'kl. 10',
      'no meaning',
    ]) {
      expect(exported, isNot(contains(secret)));
    }
    final types = [
      for (final line in const LineSplitter().convert(exported))
        jsonDecode(line)['type'],
    ];
    expect(types, [
      'header',
      'assist_prompt',
      'assist_proposal',
      'suggestion_applied',
      'meaning_changed',
      'meaning_sent',
      'meaning_changed',
      'meaning_sent',
      'meaning_removed',
    ]);
    // The file has the same events, and the export itself at the end.
    final lines = await file.readAsLines();
    expect(lines, hasLength(types.length));
    expect(jsonDecode(lines.last)['type'], 'log_exported');

    draft.dispose();
    text.dispose();
    manager.dispose();
    accessibility.dispose();
    StudyLog.instance = null;
    report('PASSED');
  });
}
