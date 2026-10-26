// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// A function call the model proposed. Not yet validated: see
/// `SettingsCallValidator`.
class ProposedCall {
  final String name;
  final Map<String, Object?> args;

  const ProposedCall(this.name, this.args);

  @override
  String toString() => 'ProposedCall($name, $args)';
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

/// Turns what the user says or types into a proposed settings change. The
/// rest of the app only knows this interface, so the model can be swapped.
///
/// Everything runs on the device. A proposal is never applied directly: it is
/// validated against the allowlist and shown to the user for confirmation.
abstract class SettingsIntentModel {
  ValueListenable<ModelStatus> get status;

  /// Prepares the model for first use. Safe to call again.
  Future<void> prepare();

  /// The model's proposed call for [text], or null when it made none.
  Future<ProposedCall?> propose(String text);

  /// Frees the loaded model's memory. The next [propose] loads it again.
  Future<void> release();

  void dispose();
}
