// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../model/settings_intent_model.dart';
import 'assist_backend.dart';
import 'assist_result.dart';

/// Asks the online assistant first and falls back to the on-device model
/// when the proxy cannot answer: no network, a timeout, the proxy's
/// ASSIST_FALLBACK (no provider answered), or the per-user rate limit.
///
/// After a network failure the online assistant is skipped for
/// [offlineCooldown] while the on-device model is ready, so someone without
/// a connection does not wait for a timeout on every prompt.
class HybridAssistBackend extends AssistBackend {
  final AssistBackend? remote;
  final AssistBackend? local;
  final Duration offlineCooldown;
  final DateTime Function() now;

  HybridAssistBackend({
    this.remote,
    this.local,
    this.offlineCooldown = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  static final ValueNotifier<ModelStatus> _unavailable = ValueNotifier(
    const ModelStatus(ModelState.unavailable),
  );

  DateTime? _skipRemoteUntil;

  /// Ready whenever the online assistant is configured; otherwise the
  /// on-device model's own state.
  @override
  ValueListenable<ModelStatus> get status =>
      remote?.status ?? local?.status ?? _unavailable;

  @override
  ValueListenable<ModelStatus>? get offlineStatus =>
      remote == null ? null : local?.status;

  bool get _localReady => local?.status.value.state == ModelState.ready;

  @override
  Future<void> prepare() async => local?.prepare();

  @override
  Future<AssistOutcome> ask(AssistRequest request) async {
    final remote = this.remote;
    final skip = _skipRemoteUntil;
    final skipRemote = skip != null && now().isBefore(skip) && _localReady;
    AssistBackendUnavailable? failure;
    if (remote != null && !skipRemote) {
      try {
        final outcome = await remote.ask(request);
        _skipRemoteUntil = null;
        return outcome;
      } on AssistBackendUnavailable catch (e) {
        failure = e;
        if (e.network) _skipRemoteUntil = now().add(offlineCooldown);
        Logs().i('Online assistant unavailable (${e.reason})');
      }
    }

    final local = this.local;
    if (local != null && _localReady) {
      final outcome = await local.ask(request);
      return AssistOutcome(
        outcome.result,
        AssistSource(
          AssistBackendKind.local,
          fallbackReason: failure?.reason ?? (skipRemote ? 'offline' : null),
        ),
        timing: outcome.timing,
      );
    }
    return AssistOutcome(
      AssistUnavailable(
        failure?.rateLimited ?? false
            ? AssistUnavailableReason.rateLimited
            : AssistUnavailableReason.offline,
      ),
      AssistSource(AssistBackendKind.remote, fallbackReason: failure?.reason),
    );
  }

  @override
  void dispose() {
    remote?.dispose();
    local?.dispose();
  }
}
