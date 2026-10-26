// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../accessibility_settings.dart';
import '../signals/interaction_signal.dart';
import 'heuristic.dart';

/// A proposed settings change, always shown to the user before it applies.
class Suggestion {
  final Heuristic heuristic;
  final ScaleCategory category;
  final double from;
  final double to;

  const Suggestion({
    required this.heuristic,
    required this.category,
    required this.from,
    required this.to,
  });
}

/// Evaluates heuristics against the rolling signal window. Rules only, no
/// model.
class HeuristicsEngine {
  final List<Heuristic> heuristics;

  const HeuristicsEngine(this.heuristics);

  /// All suggestions whose condition holds, in file order. A heuristic whose
  /// category is already at its maximum suggests nothing.
  List<Suggestion> evaluate(
    List<InteractionSignal> signals,
    AccessibilitySettings settings,
    DateTime now,
  ) => [
    for (final heuristic in heuristics)
      if (heuristic.condition.isMetBy(signals, now))
        ?_suggestionFor(heuristic, settings),
  ];

  Suggestion? _suggestionFor(
    Heuristic heuristic,
    AccessibilitySettings settings,
  ) {
    final category = heuristic.category;
    final from = settings[category];
    final to = category.normalize(from + heuristic.steps * category.step);
    if (to == from) return null;
    return Suggestion(
      heuristic: heuristic,
      category: category,
      from: from,
      to: to,
    );
  }
}
