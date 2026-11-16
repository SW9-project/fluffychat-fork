// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Phase 5 check on a device: the study log writes to the app's private
// storage, and a saved export keeps what was typed in the Assist tab. A
// stand-in model answers (FunctionGemma does not run on the x86_64 emulator),
// so no homeserver is needed.
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
import 'package:fluffychat/personalization/model/personalization_tools.dart';
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
    List<ModelTurn> conversation,
    List<FunctionDeclaration> functions,
  ) async {
    lastTiming = const ModelTiming(totalMs: 1);
    return const ProposedCall('change_button_size', {'direction': 'bigger'});
  }

  @override
  Future<void> release() async {}

  @override
  void dispose() {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a saved study log keeps the assist prompt', (tester) async {
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
            tools: PersonalizationTools.load(),
            themeMode: () => ThemeMode.system,
            chats: () => const [],
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
    final types = [
      for (final line in const LineSplitter().convert(exported))
        jsonDecode(line)['type'],
    ];
    expect(types, [
      'header',
      'assist_prompt',
      'assist_proposal',
      'suggestion_applied',
    ]);
    // The file has the same events, and the export itself at the end.
    final lines = await file.readAsLines();
    expect(lines, hasLength(types.length));
    expect(jsonDecode(lines.last)['type'], 'log_exported');

    manager.dispose();
    accessibility.dispose();
    StudyLog.instance = null;
    report('PASSED');
  });
}
