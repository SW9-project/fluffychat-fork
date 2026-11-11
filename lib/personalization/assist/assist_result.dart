// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../accessibility_settings.dart';
import '../heuristics/heuristic.dart';
import '../model/settings_call_validator.dart';

/// What the Assist tab does with the answer to one prompt, after our own
/// code has checked it. A model never produces one of these directly.
sealed class AssistResult {
  const AssistResult();
}

/// A change within the allowed range, justified by [heuristic]. It is only
/// shown; the user decides whether it is applied.
class AssistProposal extends AssistResult {
  final Heuristic heuristic;
  final ScaleCategory category;
  final double from;
  final double to;

  /// The online model's plain-language reason, already cleaned up. Null for
  /// the on-device model, which uses the heuristic's premade description.
  final String? rationale;

  /// The model asked for a value outside the range and it was clamped.
  final bool clamped;

  const AssistProposal(
    this.heuristic,
    this.category,
    this.from,
    this.to, {
    this.rationale,
    this.clamped = false,
  });
}

/// A change was asked for, but the setting cannot go further that way.
class AssistAtLimit extends AssistResult {
  final Heuristic heuristic;
  final ScaleCategory category;

  const AssistAtLimit(this.heuristic, this.category);
}

/// No usable change: no call, an unknown tool or setting, or unusable
/// arguments. The app never invents a change in this case.
class AssistNoSuggestion extends AssistResult {
  final RejectionReason reason;

  const AssistNoSuggestion(this.reason);
}

/// The online model answered in words: a short clarifying question, or a
/// kind "I can't change that".
class AssistMessage extends AssistResult {
  final String text;

  const AssistMessage(this.text);
}

/// Neither the online nor the on-device assistant could answer.
class AssistUnavailable extends AssistResult {
  final AssistUnavailableReason reason;

  /// For [AssistUnavailableReason.rateLimited]: how long until the online
  /// assistant is asked again, if known.
  final Duration? retryAfter;

  const AssistUnavailable(this.reason, {this.retryAfter});
}

/// Which assistant answered, shown subtly under the answer and logged.
enum AssistBackendKind {
  /// The online model, through our proxy.
  remote,

  /// The on-device model.
  local,
}

class AssistSource {
  final AssistBackendKind kind;

  /// The proxy's provider and model, for [AssistBackendKind.remote].
  final String? provider;
  final String? model;

  /// Why the on-device model answered instead of the online one, if it did.
  final String? fallbackReason;

  const AssistSource(
    this.kind, {
    this.provider,
    this.model,
    this.fallbackReason,
  });

  static const local = AssistSource(AssistBackendKind.local);

  Map<String, Object?> toJson() => {
    'answered_by': kind.name,
    'provider': ?provider,
    'model': ?model,
    'fallback_reason': ?fallbackReason,
  };
}

enum AssistUnavailableReason {
  /// The online assistant or the network is unreachable, or it failed.
  offline,

  /// The online assistant's rate limit was hit. On the free tier it is shared
  /// by everyone using the same key, so it is not the user's fault.
  rateLimited,
}
