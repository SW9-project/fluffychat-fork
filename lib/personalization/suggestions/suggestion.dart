// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../accessibility_settings.dart';
import '../heuristics/heuristic.dart';

/// A proposed settings change, always shown to the user before it applies.
/// It comes either from a heuristic or from the user's own request through
/// the on-device model.
class Suggestion {
  /// The heuristic id, or [modelRequestId] for a request through the model.
  /// Rate limits and opt-outs are kept per id.
  final String id;

  /// Premade text per language code.
  final Map<String, String> descriptions;

  /// How long the same id stays quiet after the user declines.
  final Duration cooldown;

  final ScaleCategory category;
  final double from;
  final double to;

  static const modelRequestId = 'model-request';

  const Suggestion({
    required this.id,
    required this.descriptions,
    required this.cooldown,
    required this.category,
    required this.from,
    required this.to,
  });

  factory Suggestion.fromHeuristic(
    Heuristic heuristic, {
    required double from,
    required double to,
  }) => Suggestion(
    id: heuristic.id,
    descriptions: heuristic.descriptions,
    cooldown: heuristic.cooldown,
    category: heuristic.category,
    from: from,
    to: to,
  );

  /// True when the user asked for this change, so heuristic rate limits do
  /// not apply.
  bool get isUserRequest => id == modelRequestId;

  String description(String languageCode) =>
      descriptions[languageCode] ?? descriptions['en'] ?? '';
}
