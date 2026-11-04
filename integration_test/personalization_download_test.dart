// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Downloads the model on a real phone, through the Set up button: the progress,
// leaving the tab during the download, the checksum, and a first request. Prints
// a [download] line for each step, which also says how long the checksum takes.
//
// It needs a phone with internet access and an app with no model installed, so
// clear the app's data first. It runs the download twice, about 285 MB each.
//
// By default it fetches the model the app runs. With
// --dart-define=SW9_TEST_BASELINE=true it fetches the base model from Hugging
// Face instead, which is public and works before a new release is published. The
// plugin does not resume downloads from Hugging Face, so that run says nothing
// about resuming.
//
// Build for an arm64 phone with this file as entry point, as the phrase harness
// (personalization_model_test.dart).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/heuristic_functions.dart';
import 'package:fluffychat/personalization/model/model_installer.dart';
import 'package:fluffychat/personalization/model/model_release.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/suggestions/suggestion_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _useBaseline = bool.fromEnvironment('SW9_TEST_BASELINE');

const _baseline = ModelRelease(
  url:
      'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm',
  sha256: '680fead1cca41a23220c904500a515d06e41f5c66d130aa4a9cc5905ec529a8e',
  sizeBytes: 284426240,
);

void _report(String line) => print('[download] $line');

Future<void> _waitFor(
  FunctionGemmaModel model,
  bool Function(ModelStatus status) done,
) async {
  while (!done(model.status.value)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('download through Set up', (tester) async {
    if (!await FunctionGemmaModel.isSupported()) {
      _report('SKIPPED: needs Android 11+ and arm64');
      return;
    }
    const file = _useBaseline ? _baseline : currentModel;
    _report('file ${file.fileName} from ${file.url}');

    final store = await SharedPreferences.getInstance();
    final config = HeuristicsConfig.fromJson(
      jsonDecode(
            await rootBundle.loadString(PersonalizationLayer.heuristicsAsset),
          )
          as Map<String, Object?>,
    );
    final accessibility = AccessibilityController(store);
    final manager = SuggestionManager(
      accessibility: accessibility,
      store: store,
      config: config,
    );
    Future<void> showTab(FunctionGemmaModel? model) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: model == null
              ? const SizedBox.expand()
              : AssistView(
                  model: model,
                  manager: manager,
                  accessibility: accessibility,
                  onOpenAccessibilitySettings: () {},
                ),
        ),
      ),
    );

    // A wrong checksum: the whole file comes down, fails and goes again.
    final wrong = FunctionGemmaModel(
      file: ModelRelease(
        url: file.url,
        sha256: '0' * 64,
        sizeBytes: file.sizeBytes,
      ),
    );
    await tester.runAsync(() async {
      final clock = Stopwatch()..start();
      await wrong.prepare();
      _report(
        'wrong checksum: ${wrong.status.value.state.name}, ${clock.elapsed}',
      );
      expect(wrong.status.value.state, ModelState.failed);
      expect(wrong.status.value.error, isA<ModelChecksumException>());
      expect(await FlutterEdgeAi.isModelInstalled(file.fileName), isFalse);
      final left = File(await FlutterEdgeAi.getModelPath(file.fileName));
      expect(await left.exists(), isFalse);
      _report('wrong checksum: the file and its record are gone');
    });
    wrong.dispose();

    // Set up, through the button.
    var model = FunctionGemmaModel(file: file);
    await tester.runAsync(
      () => _waitFor(model, (s) => s.state != ModelState.unavailable),
    );
    expect(model.status.value.state, ModelState.notPrepared);
    await showTab(model);
    await tester.pump();
    final clock = Stopwatch()..start();
    await tester.tap(find.byKey(const Key('assist_setup')));
    await tester.pump();

    // Leave the tab once the download is running, and come back.
    var progressWhenLeaving = 0;
    await tester.runAsync(() async {
      await _waitFor(
        model,
        (s) => (s.progress ?? 0) >= 5 || s.state != ModelState.preparing,
      );
      progressWhenLeaving = model.status.value.progress ?? 0;
      _report('leaving the tab at $progressWhenLeaving%, ${clock.elapsed}');
    });
    expect(model.status.value.state, ModelState.preparing);
    await showTab(null);
    model.dispose();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );

    model = FunctionGemmaModel(file: file);
    await tester.runAsync(
      () => _waitFor(model, (s) => s.state != ModelState.unavailable),
    );
    await showTab(model);
    await tester.pump();
    final back = model.status.value;
    _report('back in the tab: ${back.state.name}, ${back.progress}%');
    expect(back.state, ModelState.preparing);
    expect(back.progress, greaterThanOrEqualTo(progressWhenLeaving));
    expect(find.byKey(const Key('assist_setup')), findsNothing);

    // The rest of the download, and the check.
    final seen = <int>[];
    final checking = Stopwatch();
    model.status.addListener(() {
      final status = model.status.value;
      final progress = status.progress;
      if (progress != null) seen.add(progress);
      if (status.state == ModelState.verifying) checking.start();
      if (status.state == ModelState.ready) checking.stop();
    });
    await tester.runAsync(() async {
      await _waitFor(
        model,
        (s) => s.state == ModelState.ready || s.state == ModelState.failed,
      );
    });
    clock.stop();
    _report(
      'download and check: ${clock.elapsed}, the check: ${checking.elapsed}, '
      '${seen.length} progress updates',
    );
    expect(model.status.value.state, ModelState.ready);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    await tester.pump();
    expect(find.byKey(const Key('assist_input')), findsOneWidget);

    final installed = await tester.runAsync(
      () => FlutterEdgeAi.getModelPath(file.fileName),
    );
    final size = await tester.runAsync(() => File(installed!).length());
    final hash = await tester.runAsync(() => sha256OfFile(installed!));
    _report('installed $size bytes, sha256 $hash');
    expect(size, file.sizeBytes);
    expect(hash, file.sha256);
    expect(store.getString(ModelInstaller.verifiedKey), file.sha256);

    // A first request on the file.
    await tester.runAsync(() async {
      final call = await model.propose(
        'The buttons are too small',
        HeuristicFunctions.declarationsFor(config.heuristics),
      );
      _report('first request: $call, ${model.lastTiming?.toJson()}');
    });
    await showTab(null);
    model.dispose();

    // The next time the tab opens, it is ready at once.
    final again = FunctionGemmaModel(file: file);
    await tester.runAsync(() async {
      final opening = Stopwatch()..start();
      await _waitFor(again, (s) => s.state != ModelState.unavailable);
      _report(
        'next open: ${again.status.value.state.name}, ${opening.elapsed}',
      );
    });
    expect(again.status.value.state, ModelState.ready);
    again.dispose();

    _report('DONE');
  }, timeout: const Timeout(Duration(minutes: 40)));
}
