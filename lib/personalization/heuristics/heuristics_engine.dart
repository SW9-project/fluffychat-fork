// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../accessibility_settings.dart';
import '../signals/interaction_signal.dart';
import '../suggestions/suggestion.dart';
import 'heuristic.dart';

export '../suggestions/suggestion.dart';

/// Disabled for now (Phase 3b): signals are not collected, so nothing calls
/// this. The heuristics are offered to the on-device model instead (see
/// `HeuristicFunctions`).
///
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
    return Suggestion.fromHeuristic(heuristic, from: from, to: to);
  }
}
