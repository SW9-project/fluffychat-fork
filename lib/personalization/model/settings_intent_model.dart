// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'personalization_tools.dart';

/// A function call the model proposed. Not yet validated: see
/// `ToolCallInterpreter`.
class ProposedCall {
  final String name;
  final Map<String, Object?> args;

  const ProposedCall(this.name, this.args);

  /// This call with [key] set to [value], to answer a question of the app.
  ProposedCall withArg(String key, Object? value) =>
      ProposedCall(name, {...args, key: value});

  @override
  String toString() => 'ProposedCall($name, $args)';
}

/// One step of a conversation with the model, in the shapes it was trained
/// on (see `training/README.md`, Conversations).
sealed class ModelTurn {
  const ModelTurn();
}

/// What the user typed.
class UserTurn extends ModelTurn {
  final String text;

  const UserTurn(this.text);
}

/// A call the model made.
class CallTurn extends ModelTurn {
  final ProposedCall call;

  const CallTurn(this.call);
}

/// The app's answer to a call: the user's choice for `ask_clarification`, or
/// whether a change was applied or declined.
class ResponseTurn extends ModelTurn {
  final String name;
  final Map<String, Object?> response;

  const ResponseTurn(this.name, this.response);
}

/// The fixed reply after an answered change, such as `Done.`.
class ReplyTurn extends ModelTurn {
  final String text;

  const ReplyTurn(this.text);
}

enum ModelState {
  /// This device or build cannot run the model. The feature is hidden.
  unavailable,

  /// The model can run but is not prepared yet (first use).
  notPrepared,

  /// The model file is being prepared. See [ModelStatus.progress].
  preparing,

  /// Ready to take requests. The model is loaded on demand.
  ready,

  /// Preparing or loading failed. See [ModelStatus.error].
  failed,
}

class ModelStatus {
  final ModelState state;

  /// 0 to 100 while [ModelState.preparing], if known.
  final int? progress;
  final Object? error;

  const ModelStatus(this.state, {this.progress, this.error});

  static const unavailable = ModelStatus(ModelState.unavailable);

  bool get isUsable => state == ModelState.ready;
}

/// How long one [SettingsIntentModel.propose] took, for the study log and
/// the model test harness.
class ModelTiming {
  /// From sending the prompt to the model's answer. Loading the model is not
  /// included, see [loadMs].
  final int totalMs;

  /// Time to the first generated token as the runtime measured it, if it
  /// reports it.
  final double? timeToFirstTokenMs;

  /// How long loading the model into memory took, when this request had to
  /// load it.
  final int? loadMs;

  /// The hardware the model ran on, such as `gpu` or `cpu`, if known.
  final String? backend;

  final int? inputTokens;
  final int? outputTokens;

  const ModelTiming({
    required this.totalMs,
    this.timeToFirstTokenMs,
    this.loadMs,
    this.backend,
    this.inputTokens,
    this.outputTokens,
  });

  Map<String, Object?> toJson() => {
    'total_ms': totalMs,
    if (timeToFirstTokenMs != null) 'ttft_ms': timeToFirstTokenMs!.round(),
    if (loadMs != null) 'load_ms': loadMs,
    if (backend != null) 'backend': backend,
    if (inputTokens != null) 'input_tokens': inputTokens,
    if (outputTokens != null) 'output_tokens': outputTokens,
  };
}

/// Turns what the user says or types into a proposed settings change. The
/// rest of the app only knows this interface, so the model can be swapped.
///
/// Everything runs on the device. A proposal is never applied directly: it is
/// validated against the allowlist and shown to the user for confirmation.
abstract class SettingsIntentModel {
  ValueListenable<ModelStatus> get status;

  /// Prepares the model for first use. Safe to call again.
  Future<void> prepare();

  /// The model's next call in [conversation], choosing only among
  /// [functions], or null when it made none. The last turn is the user's
  /// text or the answer to the model's last call; the turns before it are the
  /// earlier exchange. Only what the user typed and chose in the Assist tab is
  /// sent, never messages or other chat data.
  Future<ProposedCall?> propose(
    List<ModelTurn> conversation,
    List<FunctionDeclaration> functions,
  );

  /// The timing of the last [propose] that got an answer, or null.
  ModelTiming? get lastTiming;

  /// Frees the loaded model's memory. The next [propose] loads it again.
  Future<void> release();

  void dispose();
}
