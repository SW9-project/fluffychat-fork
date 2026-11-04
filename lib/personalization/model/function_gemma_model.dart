// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:matrix/matrix.dart';

import 'model_installer.dart';
import 'model_release.dart';
import 'process_abi.dart';
import 'settings_functions.dart';
import 'settings_intent_model.dart';

/// [SettingsIntentModel] backed by FunctionGemma 270M through flutter_edge_ai
/// and the LiteRT-LM engine. Inference runs fully on the device.
///
/// The model file is downloaded when the user taps Set up, or comes from the
/// assets in a study build (see `assets/models/README.md`). A device below
/// Android 11 (API 30), a process that is not arm64 or a study build without the
/// file reports [ModelState.unavailable], and the app works without it.
class FunctionGemmaModel implements SettingsIntentModel {
  /// The file this build runs.
  static String get fileName => currentModel.fileName;

  /// The loaded model is freed after this long without a request.
  static const idleTimeout = Duration(minutes: 2);

  static Future<void>? _engineInit;

  /// One per file, for as long as the app runs. See [ModelInstaller].
  static final Map<String, ModelInstaller> _installers = {};

  final ModelRelease _file;
  final ModelFiles _files;
  final Future<bool> Function() _supported;

  final ValueNotifier<ModelStatus> _status = ValueNotifier(
    ModelStatus.unavailable,
  );
  ModelInstaller? _installer;
  InferenceModel? _model;
  ModelTiming? _lastTiming;

  /// Completes once the initial status is known.
  late final Future<void> _availability;
  Timer? _idleTimer;
  bool _disposed = false;

  FunctionGemmaModel({
    ModelRelease file = currentModel,
    @visibleForTesting ModelFiles? files,
    @visibleForTesting Future<bool> Function()? supported,
  }) : _file = file,
       _files = files ?? const _EdgeAiFiles(),
       _supported = supported ?? isSupported {
    _availability = _checkAvailability();
  }

  @visibleForTesting
  static void forgetInstallers() => _installers.clear();

  @override
  ValueListenable<ModelStatus> get status => _status;

  @override
  ModelTiming? get lastTiming => _lastTiming;

  void _setStatus(ModelStatus status) {
    if (!_disposed) _status.value = status;
  }

  /// The LiteRT-LM engine needs Android 11 and an arm64 process, and a study
  /// build must contain the model file.
  static Future<bool> isSupported() async {
    if (!PlatformInfos.isAndroid || !isAndroidArm64Process) return false;
    final info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt < 30) return false;
    // An arm64 process on an x86 device runs under ARM translation, where
    // LiteRT's CPU detection crashes the app (seen on the x86_64 emulator).
    if (info.supportedAbis.firstOrNull != 'arm64-v8a') return false;
    if (!bundledModel) return true;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().contains(currentModel.assetPath);
  }

  static Future<void> _initEngine() => _engineInit ??= FlutterEdgeAi.initialize(
    inferenceEngines: [const LiteRtLmEngine()],
  );

  Future<void> _checkAvailability() async {
    try {
      if (!await _supported()) return;
      final installer = _installers['${_file.url}#${_file.sha256}'] ??=
          ModelInstaller(file: _file, files: _files);
      await installer.refresh();
      if (_disposed) return;
      _installer = installer;
      installer.status.addListener(_followInstaller);
      _followInstaller();
    } catch (e, s) {
      Logs().w('On-device model unavailable', e, s);
      _setStatus(ModelStatus.unavailable);
    }
  }

  void _followInstaller() => _setStatus(_installer!.status.value);

  /// Only this starts a download: the user taps Set up, nothing else does.
  @override
  Future<void> prepare() async {
    await _availability;
    await _installer?.install();
  }

  Future<InferenceModel> _load() async {
    final model = _model;
    if (model != null && !model.isClosed) return model;
    final loaded = _model = await FlutterEdgeAi.getActiveModel(maxTokens: 1024);
    Logs().i('On-device model loaded, backend: ${loaded.activeBackend}');
    return loaded;
  }

  @override
  Future<ProposedCall?> propose(
    String text,
    List<FunctionDeclaration> functions,
  ) async {
    await _availability;
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
    // One fresh chat per request: earlier requests must not steer this one.
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
      // Greedy decoding: the same words always give the same proposal.
      topK: 1,
      maxOutputTokens: 128,
    );
    try {
      await chat.addQueryChunk(Message(text: text, isUser: true));
      final response = await chat.generateChatResponse();
      final metrics = _metricsOf(chat);
      _lastTiming = ModelTiming(
        totalMs: stopwatch.elapsedMilliseconds,
        timeToFirstTokenMs: metrics.timeToFirstTokenMs,
        loadMs: loadMs,
        backend: model.activeBackend?.name,
        inputTokens: metrics.inputTokens > 0 ? metrics.inputTokens : null,
        outputTokens: metrics.outputTokens > 0 ? metrics.outputTokens : null,
      );
      return switch (response) {
        FunctionCallResponse(:final name, :final args) => ProposedCall(
          name,
          args,
        ),
        ParallelFunctionCallResponse(:final calls) when calls.isNotEmpty =>
          ProposedCall(calls.first.name, calls.first.args),
        _ => null,
      };
    } finally {
      await chat.close();
      _idleTimer = Timer(idleTimeout, release);
    }
  }

  /// The runtime's own measurements for the last answer in [chat]. The tool
  /// call is not streamed, so the time to the first token can only come from
  /// here. A runtime that cannot report them never fails the request.
  static SessionMetrics _metricsOf(InferenceChat chat) {
    try {
      return chat.session.getSessionMetrics();
    } catch (e, s) {
      Logs().w('No metrics from the on-device model', e, s);
      return SessionMetrics();
    }
  }

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
    _installer?.status.removeListener(_followInstaller);
    release();
    _status.dispose();
  }
}

/// [ModelFiles] on the plugin.
class _EdgeAiFiles implements ModelFiles {
  const _EdgeAiFiles();

  @override
  Future<bool> isInstalled(String fileName) async {
    await FunctionGemmaModel._initEngine();
    return FlutterEdgeAi.isModelInstalled(fileName);
  }

  @override
  Future<void> install(
    ModelRelease file,
    void Function(int percent) onProgress,
  ) async {
    await FunctionGemmaModel._initEngine();
    final installation = FlutterEdgeAi.installModel(
      modelType: ModelType.functionGemma,
      fileType: ModelFileType.litertlm,
    );
    await (bundledModel
            ? installation.fromAsset(file.assetPath)
            : installation.fromNetwork(file.url))
        .withProgress(onProgress)
        .install();
  }

  @override
  Future<String> pathOf(String fileName) =>
      FlutterEdgeAi.getModelPath(fileName);

  @override
  Future<void> remove(String fileName) =>
      FlutterEdgeAi.uninstallModel(fileName);

  @override
  Future<List<String>> installed() => FlutterEdgeAi.listInstalledModels();
}
