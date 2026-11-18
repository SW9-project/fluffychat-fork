// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The held-out examples of the fine-tuned model, on the phone.
//
// For every example in personalization_eval_cases.dart (exported from
// training/data by training/export_eval_cases.py) this
//
// 1. sends the conversation through FunctionGemmaModel.propose, the app's own
//    path, and compares the call with the label like training/evaluate.py
//    (defaults dropped, options sorted), and
// 2. renders the same conversation with LiteRT-LM's own formatter and compares
//    it with the prompt the model was trained on, byte for byte.
//
// Build for an arm64 device or emulator with this file as entry point:
//
//   flutter test integration_test/personalization_model_test.dart -d <device>
//
// The results also go to the external files folder as eval_<model>.json:
//   adb pull /sdcard/Android/data/<app id>/files/

// ignore_for_file: avoid_print, implementation_imports, depend_on_referenced_packages

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/personalization_tools.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/model/tool_call_interpreter.dart';
import 'package:flutter_edge_ai/engine.dart';
import 'package:flutter_edge_ai_litertlm/src/ffi/litert_lm_bindings.dart';
import 'package:flutter_edge_ai_litertlm/src/ffi/litert_lm_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:path_provider/path_provider.dart';

import 'personalization_eval_cases.dart';

/// A description of the device and whether it is an emulator or simulator.
Future<(String, bool)> _device() async {
  if (Platform.isIOS) {
    final ios = await DeviceInfoPlugin().iosInfo;
    return (
      '${ios.utsname.machine} (${ios.modelName}), iOS ${ios.systemVersion}',
      !ios.isPhysicalDevice,
    );
  }
  final android = await DeviceInfoPlugin().androidInfo;
  return (
    '${android.manufacturer} ${android.model} (${android.hardware}), '
        'Android ${android.version.release}',
    !android.isPhysicalDevice,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fine-tuned model on the held-out examples', (tester) async {
    if (!await FunctionGemmaModel.isSupported()) {
      print(
        '[eval] SKIPPED: needs iOS or Android 11+, arm64 and the model file',
      );
      return;
    }
    await tester.runAsync(() async {
      final (device, emulator) = await _device();
      print('[eval] device $device, emulator: $emulator');
      final tools = await PersonalizationTools.load();
      final cases = (jsonDecode(evalCasesJson) as List)
          .cast<Map<String, Object?>>();

      final model = FunctionGemmaModel();
      final prepare = Stopwatch()..start();
      await model.prepare();
      expect(model.status.value.state, ModelState.ready);
      print('[eval] prepared in ${prepare.elapsedMilliseconds} ms');
      // A file that is already installed is not installed again, and the
      // plugin restores the model that was active last: fail rather than
      // report numbers for the wrong one.
      final active = [
        for (final f in FlutterEdgeAi.activeModelSpec?.files ?? const [])
          f.filename,
      ];
      print('[eval] active model files: $active');
      expect(active, contains(FunctionGemmaModel.fileName));

      // --dart-define=EVAL_RENDER_ONLY=true checks only the prompts.
      const renderOnly = bool.fromEnvironment('EVAL_RENDER_ONLY');
      final interpreter = ToolCallInterpreter(
        tools: tools,
        settings: AccessibilitySettings.defaults,
        theme: ThemeMode.system,
      );
      var functionOk = 0, exact = 0, usable = 0;
      final totals = <int>[];
      final results = <Map<String, Object?>>[];
      for (final c in renderOnly ? const <Map<String, Object?>>[] : cases) {
        final turns = [
          for (final m in (c['messages'] as List).cast<Map<String, Object?>>())
            _turn(m),
        ];
        final expected = c['expected'] as Map<String, Object?>;
        ProposedCall? call;
        Object? error;
        try {
          call = await model.propose(turns, tools.declarations);
        } catch (e) {
          error = e;
        }
        final timing = model.lastTiming;
        if (timing != null) totals.add(timing.totalMs);
        final want = _normalize(
          tools,
          expected['name'] as String,
          (expected['arguments'] as Map).cast<String, Object?>(),
        );
        final got = call == null
            ? null
            : _normalize(tools, call.name, call.args);
        final sameFunction = got?['name'] == want['name'];
        final same = jsonEncode(got) == jsonEncode(want);
        final result = interpreter.interpret(call);
        final ok = result is! AssistNoSuggestion;
        if (sameFunction) functionOk++;
        if (same) exact++;
        if (ok) usable++;
        results.add({
          'id': c['id'],
          'kind': c['kind'],
          'expected': want,
          'predicted': got,
          'exact': same,
          'usable': ok,
          if (error != null) 'error': '$error',
          ...?timing?.toJson(),
        });
        print(
          '[eval] ${same ? 'OK ' : 'BAD'} ${c['id']} '
          '${timing?.totalMs ?? '-'} ms -> ${got ?? error ?? 'no call'}',
        );
      }
      final backend = model.lastTiming?.backend;
      model.dispose();

      final renders = _renderAll(
        await _installedFile(),
        (await getTemporaryDirectory()).path,
        tools,
        cases,
      );
      final matching = renders.where((r) => r['matches'] == true).length;

      final n = cases.length;
      String pct(int k) => '${(100 * k / n).toStringAsFixed(1)}%';
      final whole = renders.where((r) => r['whole_prompt'] == true).length;
      print('[eval] whole prompt identical: $whole/${renders.length}');
      totals.sort();
      print('[eval] backend $backend, ${totals.length} timed requests');
      if (totals.isNotEmpty) {
        print(
          '[eval] total ms: median ${totals[totals.length ~/ 2]}, '
          'p90 ${totals[(totals.length * 0.9).floor()]}, max ${totals.last}',
        );
      }
      print('[eval] function accuracy ${pct(functionOk)} ($functionOk/$n)');
      print('[eval] exact arguments   ${pct(exact)} ($exact/$n)');
      print('[eval] usable by the app ${pct(usable)} ($usable/$n)');
      print('[eval] prompt identical to training: $matching/${renders.length}');
      // The log is the only copy once flutter test uninstalls the app.
      for (final r in renders.where((r) => r['matches'] != true).take(3)) {
        final at = r['first_difference'] as int;
        final text = r['rendered'] as String;
        print('[eval] render differs: ${r['id']} at $at');
        for (var i = 0; i < text.length && i < 1600; i += 200) {
          print(
            '[eval-render] ${jsonEncode(text.substring(i, (i + 200).clamp(0, text.length)))}',
          );
        }
        print(
          '[eval-render] ...${jsonEncode(text.substring((text.length - 400).clamp(0, text.length)))}',
        );
      }

      final out = File(
        '${(Platform.isIOS ? await getApplicationDocumentsDirectory() : await getExternalStorageDirectory())!.path}/'
        'eval_${FunctionGemmaModel.fileName}.json',
      );
      await out.writeAsString(
        const JsonEncoder.withIndent(' ').convert({
          'model': FunctionGemmaModel.fileName,
          'device': device,
          'emulator': emulator,
          'backend': backend,
          'function_ok': functionOk,
          'exact': exact,
          'usable': usable,
          'cases': n,
          'results': results,
          'renders': renders,
        }),
      );
      print('[eval] wrote ${out.path}');
      print('[eval] DONE');
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}

ModelTurn _turn(Map<String, Object?> m) => switch (m['role']) {
  'user' => UserTurn(m['content'] as String),
  'tool' => ResponseTurn(
    m['name'] as String,
    (m['content'] as Map).cast<String, Object?>(),
  ),
  'assistant' when m['tool_calls'] != null => CallTurn(
    ProposedCall(
      ((m['tool_calls'] as List).first as Map)['function']['name'] as String,
      ((((m['tool_calls'] as List).first as Map)['function']
                  as Map)['arguments']
              as Map)
          .cast<String, Object?>(),
    ),
  ),
  _ => ReplyTurn(m['content'] as String),
};

/// As training/evaluate.py: defaults dropped, options sorted, so writing out
/// a default is not a mistake.
Map<String, Object?> _normalize(
  PersonalizationTools tools,
  String name,
  Map<String, Object?> args,
) => {
  'name': name,
  'arguments': Map.fromEntries(
    [
      for (final MapEntry(:key, :value) in args.entries)
        if (value != tools.defaultOf(name, key))
          MapEntry(key, value is List ? ([...value]..sort()) : value),
    ]..sort((a, b) => a.key.compareTo(b.key)),
  ),
};

/// Where FunctionGemmaModel's file was installed.
Future<String> _installedFile() async {
  for (final root in [
    await getApplicationDocumentsDirectory(),
    await getApplicationSupportDirectory(),
  ]) {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith(FunctionGemmaModel.fileName)) {
        return entity.path;
      }
    }
  }
  throw StateError('${FunctionGemmaModel.fileName} is not installed');
}

/// Renders every case with LiteRT-LM on its own engine: the functions as
/// FunctionGemmaModel sends them, the earlier turns as the `messages_json`
/// preface and the last turn as the message.
List<Map<String, Object?>> _renderAll(
  String modelPath,
  String cacheDir,
  PersonalizationTools tools,
  List<Map<String, Object?>> cases,
) {
  final b = LiteRtLmBindings(openLiteRtLmLibrary());
  final path = modelPath.toNativeUtf8();
  final backend = 'cpu'.toNativeUtf8();
  final cache = cacheDir.toNativeUtf8();
  final settings = b.litert_lm_engine_settings_create(
    path.cast(),
    backend.cast(),
    nullptr,
    nullptr,
  );
  if (settings == nullptr) throw StateError('no engine settings');
  b.litert_lm_engine_settings_set_max_num_tokens(
    settings,
    FunctionGemmaModel.maxTokens,
  );
  b.litert_lm_engine_settings_set_cache_dir(settings, cache.cast());
  final engine = b.litert_lm_engine_create(settings);
  b.litert_lm_engine_settings_delete(settings);
  calloc
    ..free(path)
    ..free(backend)
    ..free(cache);
  if (engine == nullptr) throw StateError('no engine for $modelPath');
  final toolsJson = SdkResponseParser.serializeToolsForSdk([
    for (final f in tools.declarations)
      Tool(name: f.name, description: f.description, parameters: f.parameters),
  ]);
  try {
    return [
      for (final c in cases)
        _render(b, engine, toolsJson, c, [
          for (final m in (c['messages'] as List).cast<Map<String, Object?>>())
            _turn(m),
        ]),
    ];
  } finally {
    b.litert_lm_engine_delete(engine);
  }
}

Map<String, Object?> _render(
  LiteRtLmBindings b,
  Pointer<LiteRtLmEngine> engine,
  String toolsJson,
  Map<String, Object?> c,
  List<ModelTurn> turns,
) {
  final earlier = turns.sublist(0, turns.length - 1);
  final messages = earlier.isEmpty
      ? null
      : jsonEncode([for (final t in earlier) FunctionGemmaModel.messageOf(t)]);
  final sessionConfig = b.litert_lm_session_config_create();
  b.litert_lm_session_config_set_max_output_tokens(
    sessionConfig,
    FunctionGemmaModel.maxOutputTokens,
  );
  final toolsPtr = toolsJson.toNativeUtf8();
  final messagesPtr = messages?.toNativeUtf8();
  final config = b.litert_lm_conversation_config_create();
  b.litert_lm_conversation_config_set_session_config(config, sessionConfig);
  b.litert_lm_conversation_config_set_tools(config, toolsPtr.cast());
  b.litert_lm_conversation_config_set_enable_constrained_decoding(config, true);
  if (messagesPtr != null) {
    b.litert_lm_conversation_config_set_messages(config, messagesPtr.cast());
  }
  b.litert_lm_session_config_delete(sessionConfig);
  final conversation = b.litert_lm_conversation_create(engine, config);
  b.litert_lm_conversation_config_delete(config);
  calloc.free(toolsPtr);
  if (messagesPtr != null) calloc.free(messagesPtr);
  if (conversation == nullptr) throw StateError('no conversation');
  final message = jsonEncode(
    FunctionGemmaModel.messageOf(turns.last),
  ).toNativeUtf8();
  try {
    final rendered = b.litert_lm_conversation_render_message_to_string(
      conversation,
      message.cast(),
    );
    if (rendered == nullptr) throw StateError('render failed for ${c['id']}');
    final text = rendered.cast<Utf8>().toDartString();
    final want =
        declarationsPrompt + (c['prompt_after_declarations'] as String);
    // The render may leave out the start token, which the engine adds, or
    // hold only what this message adds after the preface.
    final matches = text == want || '<bos>$text' == want || want.endsWith(text);
    var at = 0;
    while (at < text.length && at < want.length && text[at] == want[at]) {
      at++;
    }
    return {
      'id': c['id'],
      'matches': matches,
      'whole_prompt': text == want || '<bos>$text' == want,
      if (!matches) 'first_difference': at,
      if (!matches) 'rendered': text,
    };
  } finally {
    calloc.free(message);
    b.litert_lm_conversation_delete(conversation);
  }
}
