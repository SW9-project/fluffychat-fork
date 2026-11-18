// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// flutter_edge_ai has no public way to open a conversation with earlier
// turns, which the trained conversations need. This uses the engine's own
// conversation handle, as its sessions do inside the plugin.
// ignore_for_file: implementation_imports

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/src/ffi/ffi_inference_model.dart';
import 'package:matrix/matrix.dart';

/// Sends [messageJson] in a fresh LiteRT-LM conversation with the functions in
/// [toolsJson] and, as its `messages_json` preface, the earlier turns in
/// [messagesJson]. The engine renders both with the model's own FunctionGemma
/// format, and greedy decoding makes the same words always give the same
/// answer. Returns the raw SDK response and the runtime's measurements.
Future<({String raw, SessionMetrics metrics})> runLiteRtConversation(
  InferenceModel model, {
  required String toolsJson,
  required String? messagesJson,
  required String messageJson,
  required int maxOutputTokens,
}) async {
  if (model is! FfiInferenceModel) {
    throw StateError('Expected the LiteRT-LM engine, got $model');
  }
  final client = model.ffiClient;
  final handle = await client.createConversationHandle(
    toolsJson: toolsJson,
    messagesJson: messagesJson,
    sampling: SamplingParams.resolve(
      const SamplingParams(topK: 1),
      modelType: ModelType.functionGemma,
      modelDefaults: client.bundleSampler,
    ),
    samplingExplicit: true,
    maxOutputTokens: maxOutputTokens,
    multimodalOrder: model.multimodalOrder,
  );
  try {
    final raw = StringBuffer();
    await for (final chunk in handle.chatRawMessage(messageJson)) {
      raw.write(chunk);
    }
    SessionMetrics metrics;
    try {
      metrics = handle.getSessionMetrics();
    } catch (e, s) {
      // A runtime that cannot report them never fails the request.
      Logs().w('No metrics from the on-device model', e, s);
      metrics = SessionMetrics();
    }
    return (raw: raw.toString(), metrics: metrics);
  } finally {
    handle.close();
  }
}
