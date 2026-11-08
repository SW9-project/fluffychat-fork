// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The model test harness (Phase 5): runs the phrase list through the real
// on-device model and prints a report with accuracy and latency. Since
// Phase 3b the model is offered only the heuristic functions from
// assets/personalization_heuristics.json. The phrase list is in
// personalization_phrases.dart.
//
// Latency per phrase: time to first token as LiteRT-LM measured it, and the
// total from sending the prompt to the answer. Loading the model is reported
// once, not in the totals. `[phrases-csv]` lines can be pasted into a
// spreadsheet.
//
// Needs an arm64 process on Android 11+. The first run downloads the model, so
// it needs internet access too, unless this is a study build. On a phone:
//   flutter test integration_test/personalization_model_test.dart -d <id>
// On an x86_64 emulator, build an arm64 APK with this file as entry point:
//   flutter build apk --debug --target-platform android-arm64 \
//     -t integration_test/personalization_model_test.dart
// then install it and read the report from `adb logcat -s flutter`.
// Numbers for the thesis come from a real low-end phone, never an emulator.

import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/heuristic_functions.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'personalization_phrases.dart';

enum Outcome { correct, rejected, wrong }

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FunctionGemma phrase list', (tester) async {
    if (!await FunctionGemmaModel.isSupported()) {
      // ignore: avoid_print
      print('[phrases] SKIPPED: needs Android 11+ and arm64');
      return;
    }

    await tester.runAsync(() async {
      // One print per line: Android cuts long log lines.
      // ignore: avoid_print
      void report(String line) => print(line);

      final android = await DeviceInfoPlugin().androidInfo;
      report(
        '[phrases] device ${android.manufacturer} ${android.model} '
        '(${android.hardware}), Android ${android.version.release} '
        '(API ${android.version.sdkInt})',
      );

      final heuristics = HeuristicsConfig.fromJson(
        jsonDecode(
              await rootBundle.loadString(PersonalizationLayer.heuristicsAsset),
            )
            as Map<String, Object?>,
      ).heuristics;
      final functions = HeuristicFunctions.declarationsFor(heuristics);
      final model = FunctionGemmaModel();
      final prepare = Stopwatch()..start();
      await model.prepare();
      expect(model.status.value.state, ModelState.ready);
      prepare.stop();

      // A file that is already installed is not installed again, and the
      // plugin restores the model that was active last. So a build with another
      // file can silently run the previous model until the app's data is
      // cleared: fail rather than report numbers for the wrong one.
      final activeFiles = [
        for (final f in FlutterEdgeAi.activeModelSpec?.files ?? const [])
          f.filename,
      ];
      report('[phrases] active model files: $activeFiles');
      report('[phrases] this build expects: ${FunctionGemmaModel.fileName}');
      expect(activeFiles, contains(FunctionGemmaModel.fileName));

      final counts = {for (final o in Outcome.values) o: 0};
      final correct = <String, int>{};
      final asked = <String, int>{};
      final totals = <int>[];
      final firstTokens = <double>[];
      int? loadMs;
      String? backend;
      report(
        '[phrases-csv] language,outcome,ttft_ms,total_ms,input_tokens,'
        'output_tokens,expected,proposed,text',
      );
      for (final phrase in phrases) {
        final call = await model.propose(phrase.text, functions);
        final timing = model.lastTiming!;
        loadMs ??= timing.loadMs;
        backend ??= timing.backend;
        totals.add(timing.totalMs);
        final firstToken = timing.timeToFirstTokenMs;
        if (firstToken != null) firstTokens.add(firstToken);

        final result = HeuristicFunctions.interpret(
          call,
          heuristics,
          AccessibilitySettings.defaults,
        );
        final proposed = switch (result) {
          AssistProposal(:final heuristic) => HeuristicFunctions.nameFor(
            heuristic,
          ),
          _ => null,
        };
        final outcome = proposed == null
            ? (phrase.accept.isEmpty ? Outcome.correct : Outcome.rejected)
            : (phrase.accept.contains(proposed)
                  ? Outcome.correct
                  : Outcome.wrong);
        counts[outcome] = counts[outcome]! + 1;
        asked[phrase.language] = (asked[phrase.language] ?? 0) + 1;
        if (outcome == Outcome.correct) {
          correct[phrase.language] = (correct[phrase.language] ?? 0) + 1;
        }

        report(
          '[phrases] ${phrase.language} ${outcome.name.padRight(8)} '
          'ttft ${_ms(firstToken).padLeft(5)} ms, '
          'total ${_ms(timing.totalMs).padLeft(5)} ms  '
          '"${phrase.text}" -> ${proposed ?? 'no suggestion'} (raw: $call)',
        );
        report(
          '[phrases-csv] ${[phrase.language, outcome.name, _ms(firstToken), timing.totalMs, timing.inputTokens ?? '', timing.outputTokens ?? '', phrase.accept.isEmpty ? 'none' : phrase.accept.join('|'), proposed ?? 'none', '"${phrase.text.replaceAll('"', '""')}"'].join(',')}',
        );
      }
      model.dispose();

      report(
        '[phrases] backend ${backend ?? 'unknown'}, '
        'prepare ${prepare.elapsedMilliseconds} ms, '
        'load ${_ms(loadMs)} ms',
      );
      report(
        '[phrases] ${phrases.length} phrases: '
        '${counts[Outcome.correct]} correct, '
        '${counts[Outcome.rejected]} no suggestion where one fits, '
        '${counts[Outcome.wrong]} wrong',
      );
      for (final language in asked.keys) {
        report(
          '[phrases] $language: ${correct[language] ?? 0} of '
          '${asked[language]} correct',
        );
      }
      report('[phrases] time to first token: ${_stats(firstTokens)}');
      report('[phrases] total: ${_stats(totals)}');
    });
  });
}

String _ms(num? value) => value == null ? '-' : value.round().toString();

String _stats(List<num> values) {
  if (values.isEmpty) return 'not reported';
  final sorted = [...values]..sort();
  num at(double quantile) => sorted[((sorted.length - 1) * quantile).round()];
  return 'median ${_ms(at(0.5))} ms, p90 ${_ms(at(0.9))} ms, '
      'max ${_ms(sorted.last)} ms';
}
