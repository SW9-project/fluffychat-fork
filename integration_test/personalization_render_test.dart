// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Asks LiteRT-LM on the phone for the exact prompt it builds, so the training
// data can be made to match it byte for byte.
//
// For every case in personalization_render_cases.dart, and for each model file
// it finds, this opens a conversation the way flutter_edge_ai does for one
// request (tools_json, constrained decoding, no system message), renders the
// user's message with litert_lm_conversation_render_message_to_string and
// tokenizes the result with the file's own tokenizer. It also makes a few real
// requests on each file through FunctionGemmaModel's path, to record what the
// plugin returns, on which backend, and how many tokens the model really got.
//
// Model files: the one FunctionGemmaModel installs, and any .litertlm pushed to
// the app's external files folder.
//
// The results go to the external files folder as render_<file>.json:
//   adb pull /sdcard/Android/data/<app id>/files/
//
// Build for an arm64 phone with this file as entry point, as the phrase
// harness (personalization_model_test.dart).

// ignore_for_file: avoid_print, implementation_imports, depend_on_referenced_packages

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/heuristic_functions.dart';
import 'package:fluffychat/personalization/model/settings_functions.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/engine.dart';
import 'package:flutter_edge_ai_litertlm/src/ffi/litert_lm_bindings.dart';
import 'package:flutter_edge_ai_litertlm/src/ffi/litert_lm_client.dart';
import 'package:flutter_edge_ai_litertlm/src/ffi/litert_lm_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'personalization_render_cases.dart';

/// Texts sent through the real chat path, on every file.
const _realRequests = [
  'The screen is hard to use today',
  'Skærmen er svær at bruge i dag, æøå ÆØÅ',
  "What's the weather tomorrow?",
  'Hvad er klokken?',
  'The buttons are too small',
  'Make the text bigger please',
  'Gør skriften større',
  'Knapperne er for små',
];

/// Pieces of the format, to compare the file's tokenizer with the one training
/// uses.
const _pieces = [
  '<bos>',
  '<eos>',
  '<pad>',
  '<start_of_turn>',
  '<end_of_turn>',
  '<start_function_declaration>',
  '<end_function_declaration>',
  '<start_function_call>',
  '<end_function_call>',
  '<start_function_response>',
  '<end_function_response>',
  '<escape>',
  'No matching function.',
  'No matching function.<end_of_turn>',
  'developer\n',
  'call:heuristic_text_zoom{}',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('render prompts', (tester) async {
    if (!await FunctionGemmaModel.isSupported()) {
      print('[render] SKIPPED: needs Android 11+ and arm64');
      return;
    }
    await tester.runAsync(() async {
      final heuristics = HeuristicsConfig.fromJson(
        jsonDecode(
              await rootBundle.loadString(PersonalizationLayer.heuristicsAsset),
            )
            as Map<String, Object?>,
      ).heuristics;
      final appFunctions = HeuristicFunctions.declarationsFor(heuristics);

      final model = FunctionGemmaModel();
      await model.prepare();
      expect(model.status.value.state, ModelState.ready);
      final real = await _realChats(appFunctions);
      model.dispose();

      final outFolder = (await getExternalStorageDirectory())!;
      final installed = await _installedFile();
      final files = {
        installed,
        for (final f in outFolder.listSync())
          if (f is File && f.path.endsWith('.litertlm')) f.path,
      };
      print('[render] model files: $files');

      final cases = (jsonDecode(renderCasesJson) as List)
          .cast<Map<String, Object?>>();
      final bindings = LiteRtLmBindings(openLiteRtLmLibrary());
      final cache = (await getTemporaryDirectory()).path;
      for (final path in files) {
        final name = path.split('/').last;
        print('[render] $name: rendering ${cases.length} cases');
        final results = _renderAll(bindings, path, cache, cases, appFunctions);
        // A pushed file becomes the active model from here on: clear the app's
        // data before relying on what is installed.
        if (path != installed) {
          await FlutterEdgeAi.installModel(
            modelType: ModelType.functionGemma,
            fileType: ModelFileType.litertlm,
          ).fromFile(path).install();
        }
        final answers = path == installed
            ? real
            : await _realChats(appFunctions);
        final out = File('${outFolder.path}/render_$name.json');
        await out.writeAsString(
          const JsonEncoder.withIndent(' ').convert({
            'file': name,
            'size_bytes': await File(path).length(),
            'installed': path == installed,
            'active_file': FunctionGemmaModel.fileName,
            'real_requests': answers,
            ...results,
          }),
        );
        print('[render] wrote ${out.path}');
      }
      print('[render] DONE');
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// Where FunctionGemmaModel's file was installed.
Future<String> _installedFile() async {
  final roots = [
    await getApplicationDocumentsDirectory(),
    await getApplicationSupportDirectory(),
  ];
  for (final root in roots) {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith(FunctionGemmaModel.fileName)) {
        return entity.path;
      }
    }
  }
  throw StateError('${FunctionGemmaModel.fileName} is not installed');
}

/// The plugin's answer to real requests, created as FunctionGemmaModel does.
Future<List<Map<String, Object?>>> _realChats(
  List<FunctionDeclaration> functions,
) async {
  final model = await FlutterEdgeAi.getActiveModel(maxTokens: 1024);
  final results = <Map<String, Object?>>[];
  for (final text in _realRequests) {
    final chat = await model.createChat(
      tools: [
        for (final f in functions)
          Tool(
            name: f.name,
            description: f.description,
            parameters: f.parameters,
          ),
      ],
      supportsFunctionCalls: true,
      modelType: ModelType.functionGemma,
      topK: 1,
      maxOutputTokens: 128,
    );
    final session = chat.session;
    final stopwatch = Stopwatch()..start();
    await chat.addQueryChunk(Message(text: text, isUser: true));
    final response = await chat.generateChatResponse();
    final totalMs = stopwatch.elapsedMilliseconds;
    SessionMetrics? afterAnswer;
    try {
      afterAnswer = chat.session.getSessionMetrics();
    } catch (_) {}
    results.add({
      'text': text,
      'response_type': response.runtimeType.toString(),
      'response': response.toString(),
      'raw': session is RawSdkResponseSession ? session.lastRawResponse : null,
      'session_was_recreated': !identical(session, chat.session),
      'input_tokens': afterAnswer?.inputTokens,
      'output_tokens': afterAnswer?.outputTokens,
      'backend': model.activeBackend?.name,
      'total_ms': totalMs,
    });
    print('[render] real: ${results.last}');
    await chat.close();
  }
  await model.close();
  return results;
}

Map<String, Object?> _renderAll(
  LiteRtLmBindings b,
  String modelPath,
  String cacheDir,
  List<Map<String, Object?>> cases,
  List<FunctionDeclaration> appFunctions,
) {
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
  b.litert_lm_engine_settings_set_max_num_tokens(settings, 1024);
  b.litert_lm_engine_settings_set_cache_dir(settings, cache.cast());
  final engine = b.litert_lm_engine_create(settings);
  b.litert_lm_engine_settings_delete(settings);
  calloc
    ..free(path)
    ..free(backend)
    ..free(cache);
  if (engine == nullptr) throw StateError('no engine for $modelPath');
  try {
    return {
      'app_tools': [
        for (final f in appFunctions)
          {
            'name': f.name,
            'description': f.description,
            'parameters': f.parameters,
          },
      ],
      'pieces': {for (final p in _pieces) p: _tokenize(b, engine, p)},
      'results': [
        for (final c in cases) _renderCase(b, engine, c, appFunctions),
      ],
    };
  } finally {
    b.litert_lm_engine_delete(engine);
  }
}

Map<String, Object?> _renderCase(
  LiteRtLmBindings b,
  Pointer<LiteRtLmEngine> engine,
  Map<String, Object?> c,
  List<FunctionDeclaration> appFunctions,
) {
  final tools = c['tools'] == 'app'
      ? [
          for (final f in appFunctions)
            Tool(
              name: f.name,
              description: f.description,
              parameters: f.parameters,
            ),
        ]
      : [
          for (final f in (c['tools'] as List).cast<Map<String, Object?>>())
            Tool(
              name: f['name'] as String,
              description: f['description'] as String,
              parameters: f['parameters'] as Map<String, Object?>,
            ),
        ];
  final toolsJson = SdkResponseParser.serializeToolsForSdk(tools);
  final messageJson = LiteRtLmFfiClient.buildMessageJson(c['text'] as String);

  final conversation = _openConversation(b, engine, toolsJson);
  final message = messageJson.toNativeUtf8();
  try {
    final rendered = b.litert_lm_conversation_render_message_to_string(
      conversation,
      message.cast(),
    );
    if (rendered == nullptr) throw StateError('render failed for ${c['id']}');
    final text = rendered.cast<Utf8>().toDartString();
    return {
      'id': c['id'],
      'tools_json': toolsJson,
      'message_json': messageJson,
      'rendered': text,
      'tokens': _tokenize(b, engine, text),
    };
  } finally {
    calloc.free(message);
    b.litert_lm_conversation_delete(conversation);
  }
}

/// The same configuration as the plugin's _createRawConversation.
Pointer<LiteRtLmConversation> _openConversation(
  LiteRtLmBindings b,
  Pointer<LiteRtLmEngine> engine,
  String toolsJson,
) {
  final sessionConfig = b.litert_lm_session_config_create();
  final sampler = b.litert_lm_sampler_params_create(2);
  b.litert_lm_sampler_params_set_top_k(sampler, 1);
  b.litert_lm_sampler_params_set_top_p(sampler, 1);
  b.litert_lm_sampler_params_set_temperature(sampler, 1);
  b.litert_lm_sampler_params_set_seed(sampler, 0);
  b.litert_lm_session_config_set_sampler_params(sessionConfig, sampler);
  b.litert_lm_sampler_params_delete(sampler);
  b.litert_lm_session_config_set_max_output_tokens(sessionConfig, 128);

  final tools = toolsJson.toNativeUtf8();
  final config = b.litert_lm_conversation_config_create();
  b.litert_lm_conversation_config_set_session_config(config, sessionConfig);
  b.litert_lm_conversation_config_set_tools(config, tools.cast());
  b.litert_lm_conversation_config_set_enable_constrained_decoding(config, true);
  b.litert_lm_session_config_delete(sessionConfig);
  calloc.free(tools);

  final conversation = b.litert_lm_conversation_create(engine, config);
  b.litert_lm_conversation_config_delete(config);
  if (conversation == nullptr) throw StateError('no conversation');
  return conversation;
}

List<int> _tokenize(
  LiteRtLmBindings b,
  Pointer<LiteRtLmEngine> engine,
  String text,
) {
  final textPtr = text.toNativeUtf8();
  final result = b.litert_lm_engine_tokenize(engine, textPtr.cast());
  calloc.free(textPtr);
  if (result == nullptr) throw StateError('tokenize failed');
  try {
    final n = b.litert_lm_tokenize_result_get_num_tokens(result);
    final ids = b.litert_lm_tokenize_result_get_tokens(result);
    return [for (var i = 0; i < n; i++) ids[i]];
  } finally {
    b.litert_lm_tokenize_result_delete(result);
  }
}
