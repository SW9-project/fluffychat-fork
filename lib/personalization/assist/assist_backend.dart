// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import '../accessibility_settings.dart';
import '../model/settings_intent_model.dart';
import 'assist_result.dart';

/// An earlier exchange in the Assist tab that ended in a question from the
/// assistant, so the user's answer can be understood.
@immutable
class AssistTurn {
  final String prompt;
  final String reply;

  const AssistTurn(this.prompt, this.reply);
}

/// Everything an assistant may know for one request: what the user typed in
/// the Assist tab, at most the one exchange before it, and the current
/// accessibility settings.
///
/// This type is deliberately closed. It has no field for rooms, messages,
/// contacts or any other app data, so no backend can be handed them.
@immutable
class AssistRequest {
  final String prompt;
  final AccessibilitySettings settings;
  final AssistTurn? previous;

  const AssistRequest(this.prompt, this.settings, {this.previous});
}

/// A checked answer and who gave it.
class AssistOutcome {
  final AssistResult result;
  final AssistSource source;
  final ModelTiming? timing;

  const AssistOutcome(this.result, this.source, {this.timing});
}

/// An assistant the Assist tab can ask. Every backend validates the model's
/// answer itself and returns an [AssistResult]; nothing is applied here.
///
/// Only `AssistantPage` creates backends, so nothing outside the Assist tab
/// can reach a model.
abstract class AssistBackend {
  /// The tab shows the input only while this is [ModelState.ready].
  ValueListenable<ModelStatus> get status;

  /// The on-device model's state when it is a fallback behind an online
  /// assistant, so the tab can offer to set it up. Null otherwise.
  ValueListenable<ModelStatus>? get offlineStatus => null;

  /// Sets up the on-device model, if there is one. Safe to call again.
  Future<void> prepare();

  Future<AssistOutcome> ask(AssistRequest request);

  void dispose();
}

/// The online assistant could not answer. [reason] is a short code for the
/// logs; it never contains the user's words.
class AssistBackendUnavailable implements Exception {
  final String reason;

  /// The network or the service could not be reached at all, or did not
  /// answer in time.
  final bool network;

  /// The service's rate limit was hit (HTTP 429).
  final bool rateLimited;

  /// How long the service asked us to wait, from its `retry-after` header.
  final Duration? retryAfter;

  const AssistBackendUnavailable(
    this.reason, {
    this.network = false,
    this.rateLimited = false,
    this.retryAfter,
  });

  @override
  String toString() => 'AssistBackendUnavailable($reason)';
}
