// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Runs the phrase list through the real on-device model and prints a report.
//
// Needs an arm64 process on Android 11+ and the bundled model file
// (scripts/fetch_personalization_model.sh). On a phone:
//   flutter test integration_test/personalization_model_test.dart -d <id>
// On an x86_64 emulator, build an arm64 APK with this file as entry point:
//   flutter build apk --debug --target-platform android-arm64 \
//     -t integration_test/personalization_model_test.dart
// then install it and read the report from `adb logcat -s flutter`.
// Latency numbers from an emulator are not valid study results.

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/settings_call_validator.dart';
import 'package:fluffychat/personalization/model/settings_functions.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'personalization_phrases.dart';

enum Outcome { correct, rejected, wrong }

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FunctionGemma phrase list', (tester) async {
    if (!await FunctionGemmaModel.isSupported()) {
      // ignore: avoid_print
      print('[phrases] SKIPPED: needs Android 11+, arm64 and the model file');
      return;
    }

    await tester.runAsync(() async {
      final model = FunctionGemmaModel();
      final load = Stopwatch()..start();
      await model.prepare();
      expect(model.status.value.state, ModelState.ready);
      load.stop();

      final counts = {for (final o in Outcome.values) o: 0};
      final times = <int>[];
      // One print per line: Android cuts long log lines.
      // ignore: avoid_print
      void report(String line) => print(line);
      for (final phrase in phrases) {
        final stopwatch = Stopwatch()..start();
        final call = await model.propose(phrase.text);
        stopwatch.stop();
        times.add(stopwatch.elapsedMilliseconds);

        final result = SettingsCallValidator.validate(
          call,
          AccessibilitySettings.defaults,
        );
        final proposed = switch (result) {
          ValidCall(:final category, :final from, :final to) =>
            '${SettingsFunctions.nameFor(category)}: '
                '${to > from ? SettingsFunctions.bigger : SettingsFunctions.smaller}',
          RejectedCall() => null,
        };
        final outcome = proposed == null
            ? (phrase.accept.isEmpty ? Outcome.correct : Outcome.rejected)
            : (phrase.accept.contains(proposed)
                  ? Outcome.correct
                  : Outcome.wrong);
        counts[outcome] = counts[outcome]! + 1;
        report(
          '[phrases] ${phrase.language} ${outcome.name.padRight(8)} '
          '${stopwatch.elapsedMilliseconds.toString().padLeft(6)} ms  '
          '"${phrase.text}" -> ${proposed ?? 'rejected'} (raw: $call)',
        );
      }
      model.dispose();

      times.sort();
      report('[phrases] load ${load.elapsedMilliseconds} ms');
      report(
        '[phrases] ${phrases.length} phrases: '
        '${counts[Outcome.correct]} correct, '
        '${counts[Outcome.rejected]} safely rejected, '
        '${counts[Outcome.wrong]} wrong',
      );
      report(
        '[phrases] median ${times[times.length ~/ 2]} ms, '
        'max ${times.last} ms',
      );
    });
  });
}
