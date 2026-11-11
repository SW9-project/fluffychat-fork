// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../model/settings_intent_model.dart';
import 'assist_backend.dart';
import 'assist_result.dart';

/// Asks the online assistant first and falls back to the on-device model
/// when it cannot answer: no network, a timeout, a server error, a rejected
/// key or request, or a repeated rate limit.
///
/// Rate limits (HTTP 429) are shared by everyone on the free tier, so they
/// are handled calmly and never retried in a loop:
/// - The first one asks the user to wait a moment, even when the on-device
///   model is ready, because the online assistant is usually back within
///   seconds.
/// - Until the service's `retry-after` wait is over, the online assistant is
///   not asked at all. The on-device model answers if it is ready; otherwise
///   the user is asked to wait again.
/// - Another 429 right after, or a wait longer than [shortWait] (the daily
///   quota), goes straight to the on-device model.
///
/// After a network failure the online assistant is skipped for
/// [offlineCooldown] while the on-device model is ready, so someone without
/// a connection does not wait for a timeout on every prompt.
class HybridAssistBackend extends AssistBackend {
  final AssistBackend? remote;
  final AssistBackend? local;
  final Duration offlineCooldown;
  final DateTime Function() now;

  /// The wait after a 429 that did not say how long.
  static const defaultRateLimitWait = Duration(seconds: 20);

  /// Longer waits than this mean a quota, not a busy moment.
  static const shortWait = Duration(seconds: 60);

  /// A 429 more than this long after the last one counts as a first one.
  static const rateLimitMemory = Duration(minutes: 5);

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
  DateTime? _rateLimitedUntil;
  DateTime? _lastRateLimit;
  int _rateLimits = 0;

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
    final start = now();

    final limitedUntil = _rateLimitedUntil;
    if (remote != null &&
        limitedUntil != null &&
        start.isBefore(limitedUntil)) {
      // Still waiting after a 429: never ask the online assistant now.
      return _fallback(
        request,
        reason: 'rate_limited',
        unavailable: AssistUnavailable(
          AssistUnavailableReason.rateLimited,
          retryAfter: limitedUntil.difference(start),
        ),
      );
    }

    final skip = _skipRemoteUntil;
    final skipRemote = skip != null && start.isBefore(skip) && _localReady;
    AssistBackendUnavailable? failure;
    if (remote != null && !skipRemote) {
      try {
        final outcome = await remote.ask(request);
        _skipRemoteUntil = null;
        _rateLimitedUntil = null;
        _rateLimits = 0;
        return outcome;
      } on AssistBackendUnavailable catch (e) {
        failure = e;
        Logs().i('Online assistant unavailable (${e.reason})');
        if (e.network) _skipRemoteUntil = now().add(offlineCooldown);
        if (e.rateLimited) {
          final wait = _rememberRateLimit(e.retryAfter);
          if (_rateLimits == 1 && wait <= shortWait) {
            return AssistOutcome(
              AssistUnavailable(
                AssistUnavailableReason.rateLimited,
                retryAfter: wait,
              ),
              AssistSource(AssistBackendKind.remote, fallbackReason: e.reason),
            );
          }
        }
      }
    }

    return _fallback(
      request,
      reason: failure?.reason ?? (skipRemote ? 'offline' : null),
      unavailable: AssistUnavailable(
        failure?.rateLimited ?? false
            ? AssistUnavailableReason.rateLimited
            : AssistUnavailableReason.offline,
        retryAfter: failure?.rateLimited ?? false
            ? _rateLimitedUntil?.difference(now())
            : null,
      ),
    );
  }

  /// Notes a 429 and returns how long to leave the online assistant alone.
  Duration _rememberRateLimit(Duration? retryAfter) {
    final at = now();
    final last = _lastRateLimit;
    if (last == null || at.difference(last) > rateLimitMemory) _rateLimits = 0;
    _rateLimits++;
    _lastRateLimit = at;
    final wait = retryAfter ?? defaultRateLimitWait;
    _rateLimitedUntil = at.add(wait);
    return wait;
  }

  /// The on-device model's answer if it is ready, else [unavailable].
  Future<AssistOutcome> _fallback(
    AssistRequest request, {
    required String? reason,
    required AssistUnavailable unavailable,
  }) async {
    final local = this.local;
    if (local != null && _localReady) {
      final outcome = await local.ask(request);
      return AssistOutcome(
        outcome.result,
        AssistSource(AssistBackendKind.local, fallbackReason: reason),
        timing: outcome.timing,
      );
    }
    return AssistOutcome(
      unavailable,
      AssistSource(AssistBackendKind.remote, fallbackReason: reason),
    );
  }

  @override
  void dispose() {
    remote?.dispose();
    local?.dispose();
  }
}
