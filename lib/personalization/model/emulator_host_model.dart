// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'assistant_model_config.dart';
import 'settings_functions.dart';
import 'settings_intent_model.dart';

/// Explicit debug-build option for x86 Android emulators. The v2 model
/// runs on this computer, reached only through `adb reverse tcp:8787 tcp:8787`.
/// Normal and release builds continue to use the on-device model.
class EmulatorHostModel implements SettingsIntentModel {
  static const enabled =
      kDebugMode && bool.fromEnvironment('SW9_EMULATOR_ASSIST');

  final http.Client _client;
  final ValueNotifier<ModelStatus> _status = ValueNotifier(
    const ModelStatus(ModelState.notPrepared),
  );
  bool _disposed = false;
  ModelTiming? _lastTiming;

  EmulatorHostModel({http.Client? client}) : _client = client ?? http.Client();

  @override
  ValueListenable<ModelStatus> get status => _status;

  @override
  ModelTiming? get lastTiming => _lastTiming;

  void _setStatus(ModelStatus value) {
    if (!_disposed) _status.value = value;
  }

  @override
  Future<void> prepare() async {
    _setStatus(const ModelStatus(ModelState.preparing));
    try {
      final response = await _client
          .get(Uri.parse('http://127.0.0.1:8787/health'))
          .timeout(const Duration(seconds: 15));
      final health = response.statusCode == 200
          ? jsonDecode(response.body) as Map
          : null;
      if (health?['ready'] != true ||
          health?['model'] != AssistantModelConfig.id ||
          health?['sha256'] != AssistantModelConfig.sha256) {
        throw StateError('The local development model is not ready');
      }
      _setStatus(const ModelStatus(ModelState.ready));
    } catch (error) {
      _setStatus(ModelStatus(ModelState.failed, error: error));
    }
  }

  @override
  Future<ProposedCall?> propose(
    String text,
    List<FunctionDeclaration> functions,
  ) async {
    _lastTiming = null;
    if (_status.value.state != ModelState.ready) await prepare();
    if (_status.value.state != ModelState.ready) {
      throw StateError(
        'Start the local development assistant and reconnect adb',
      );
    }
    final watch = Stopwatch()..start();
    final response = await _client
        .post(
          Uri.parse('http://127.0.0.1:8787/propose'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'functions': [
              for (final function in functions)
                {
                  'name': function.name,
                  'description': function.description,
                  'parameters': function.parameters,
                },
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      throw StateError('Local development inference failed');
    }
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    _lastTiming = ModelTiming(
      totalMs: watch.elapsedMilliseconds,
      backend: 'development-host-cpu',
    );
    final call = result['call'];
    if (call == null) return null;
    if (call is! Map || call['name'] is! String || call['args'] is! Map) {
      throw const FormatException('Invalid development model response');
    }
    // Apply the same allowlist/range checks as the on-device model in the
    // existing AssistView. Nothing is applied until the user taps Apply.
    return ProposedCall(
      call['name'] as String,
      Map<String, Object?>.from(call['args'] as Map),
    );
  }

  @override
  Future<void> release() async {}

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    _status.dispose();
  }
}
