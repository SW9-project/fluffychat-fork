// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/engine.dart' show SdkResponseParser;
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:matrix/matrix.dart';

import 'assistant_model_config.dart';
import 'litert_conversation.dart';
import 'personalization_tools.dart';
import 'process_abi.dart';
import 'settings_intent_model.dart';

/// [SettingsIntentModel] backed by FunctionGemma 270M through flutter_edge_ai
/// and the LiteRT-LM engine. Runs fully on the device.
///
/// The model file is bundled as an app asset (see `assets/models/README.md`).
/// A build without it, a platform other than iOS or Android, an Android device
/// below 11 (API 30) or a process that is not arm64 reports
/// [ModelState.unavailable], and the app works without it.
class FunctionGemmaModel implements SettingsIntentModel {
  static const assetPath = AssistantModelConfig.assetPath;
  static const fileName = AssistantModelConfig.fileName;

  /// The model file's context: the eleven declarations are ~1300 tokens, a
  /// conversation adds up to ~200 and the answer [maxOutputTokens].
  static const maxTokens = 2048;
  static const maxOutputTokens = 128;

  /// The loaded model is freed after this long without a request.
  static const idleTimeout = Duration(minutes: 2);

  static Future<void>? _engineInit;

  final ValueNotifier<ModelStatus> _status = ValueNotifier(
    ModelStatus.unavailable,
  );
  InferenceModel? _model;
  Future<void>? _preparing;
  ModelTiming? _lastTiming;

  /// Completes once the initial status is known.
  late final Future<void> _availability;
  Timer? _idleTimer;
  bool _disposed = false;

  FunctionGemmaModel() {
    _availability = _checkAvailability();
  }

  @override
  ValueListenable<ModelStatus> get status => _status;

  @override
  ModelTiming? get lastTiming => _lastTiming;

  void _setStatus(ModelStatus status) {
    if (!_disposed) _status.value = status;
  }

  /// The LiteRT-LM engine needs an arm64 process on iOS, or on Android 11, and
  /// this build must contain the model file.
  static Future<bool> isSupported() async {
    if (PlatformInfos.isIOS) {
      return isIOSArm64Process && await _bundlesModel();
    }
    if (!PlatformInfos.isAndroid || !isAndroidArm64Process) return false;
    final info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt < 30) return false;
    // An arm64 process on an x86 device runs under ARM translation, where
    // LiteRT's CPU detection crashes the app (seen on the x86_64 emulator).
    if (info.supportedAbis.firstOrNull != 'arm64-v8a') return false;
    return _bundlesModel();
  }

  static Future<bool> _bundlesModel() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().contains(assetPath);
  }

  static Future<void> _initEngine() => _engineInit ??= FlutterEdgeAi.initialize(
    inferenceEngines: [const LiteRtLmEngine()],
  );

  Future<void> _checkAvailability() async {
    try {
      if (!await isSupported()) return;
      await _initEngine();
      final installed = await FlutterEdgeAi.isModelInstalled(fileName);
      _setStatus(
        ModelStatus(installed ? ModelState.ready : ModelState.notPrepared),
      );
    } catch (e, s) {
      Logs().w('On-device model unavailable', e, s);
      _setStatus(ModelStatus.unavailable);
    }
  }

  @override
  Future<void> prepare() =>
      _preparing ??= _prepare().whenComplete(() => _preparing = null);

  /// Copies the bundled model into the app's model storage on first use.
  Future<void> _prepare() async {
    await _availability;
    final state = _status.value.state;
    if (state == ModelState.unavailable || state == ModelState.ready) return;
    _setStatus(const ModelStatus(ModelState.preparing, progress: 0));
    try {
      await _initEngine();
      await FlutterEdgeAi.installModel(
            modelType: ModelType.functionGemma,
            fileType: ModelFileType.litertlm,
          )
          .fromAsset(assetPath)
          .withProgress(
            (percent) => _setStatus(
              ModelStatus(ModelState.preparing, progress: percent),
            ),
          )
          .install();
      _setStatus(const ModelStatus(ModelState.ready));
    } catch (e, s) {
      Logs().e('Unable to prepare the on-device model', e, s);
      _setStatus(ModelStatus(ModelState.failed, error: e));
    }
  }

  Future<InferenceModel> _load() async {
    final model = _model;
    if (model != null && !model.isClosed) return model;
    final loaded = _model = await FlutterEdgeAi.getActiveModel(
      maxTokens: maxTokens,
    );
    Logs().i('On-device model loaded, backend: ${loaded.activeBackend}');
    return loaded;
  }

  @override
  Future<ProposedCall?> propose(
    List<ModelTurn> conversation,
    List<FunctionDeclaration> functions,
  ) async {
    if (conversation.isEmpty) throw ArgumentError('Nothing to answer');
    await _availability;
    if (_status.value.state != ModelState.ready) await prepare();
    if (_status.value.state != ModelState.ready) {
      throw StateError('The on-device model is not ready');
    }
    _idleTimer?.cancel();
    _lastTiming = null;
    final stopwatch = Stopwatch()..start();
    final loaded = _model != null && !_model!.isClosed;
    final model = await _load();
    final loadMs = loaded ? null : stopwatch.elapsedMilliseconds;
    stopwatch.reset();
    // One fresh conversation per request, holding only the turns given:
    // nothing else the user asked before can steer this answer.
    try {
      final earlier = conversation.sublist(0, conversation.length - 1);
      final (:raw, :metrics) = await runLiteRtConversation(
        model,
        toolsJson: SdkResponseParser.serializeToolsForSdk([
          for (final f in functions)
            Tool(
              name: f.name,
              description: f.description,
              parameters: f.parameters,
            ),
        ]),
        messagesJson: earlier.isEmpty
            ? null
            : jsonEncode([for (final turn in earlier) messageOf(turn)]),
        messageJson: jsonEncode(messageOf(conversation.last)),
        maxOutputTokens: maxOutputTokens,
      );
      _lastTiming = ModelTiming(
        totalMs: stopwatch.elapsedMilliseconds,
        timeToFirstTokenMs: metrics.timeToFirstTokenMs,
        loadMs: loadMs,
        backend: model.activeBackend?.name,
        inputTokens: metrics.inputTokens > 0 ? metrics.inputTokens : null,
        outputTokens: metrics.outputTokens > 0 ? metrics.outputTokens : null,
      );
      final calls = SdkResponseParser.extractToolCalls(raw);
      if (calls.isEmpty) return null;
      return ProposedCall(calls.first.name, calls.first.args);
    } finally {
      _idleTimer = Timer(idleTimeout, release);
    }
  }

  /// [map] with its keys in alphabetical order. LiteRT-LM writes a call's
  /// arguments in the order it gets them, and the training template sorted
  /// them.
  static Map<String, Object?> _sorted(Map<String, Object?> map) => {
    for (final key in map.keys.toList()..sort()) key: map[key],
  };

  /// [turn] as a LiteRT-LM Conversation API message.
  @visibleForTesting
  static Map<String, Object?> messageOf(ModelTurn turn) => switch (turn) {
    UserTurn(:final text) => {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': text},
      ],
    },
    CallTurn(:final call) => {
      'role': 'assistant',
      'tool_calls': [
        {
          'type': 'function',
          'function': {'name': call.name, 'arguments': _sorted(call.args)},
        },
      ],
    },
    ResponseTurn(:final name, :final response) => {
      'role': 'tool',
      'content': [
        {'type': 'tool_response', 'name': name, 'response': _sorted(response)},
      ],
    },
    ReplyTurn(:final text) => {
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': text},
      ],
    },
  };

  @override
  Future<void> release() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final model = _model;
    _model = null;
    await model?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    release();
    _status.dispose();
  }
}
