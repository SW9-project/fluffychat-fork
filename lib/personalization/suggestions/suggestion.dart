// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart' show ThemeMode;

import '../accessibility_settings.dart';
import '../heuristics/heuristic.dart';

/// What a suggestion changes: the accessibility settings before and after,
/// and the theme when it changes too. The theme stays FluffyChat's own
/// setting, so it is not part of [AccessibilitySettings].
class SettingsChange {
  final AccessibilitySettings from;
  final AccessibilitySettings to;
  final ThemeMode? themeFrom;
  final ThemeMode? themeTo;

  const SettingsChange({
    required this.from,
    required this.to,
    this.themeFrom,
    this.themeTo,
  });

  /// One size from [from] to [to] times normal.
  factory SettingsChange.scale(
    AccessibilitySettings settings,
    ScaleCategory category,
    double to,
  ) => SettingsChange(from: settings, to: settings.copyWith(category, to));

  bool get changesTheme => themeTo != null && themeTo != themeFrom;

  bool get isEmpty => from == to && !changesTheme;

  /// The one size that changes, if exactly one does.
  ScaleCategory? get onlyCategory {
    final changed = [
      for (final c in ScaleCategory.values)
        if (from[c] != to[c]) c,
    ];
    return changed.length == 1 ? changed.single : null;
  }

  /// The chat whose own text scale changes, if any.
  String? get changedChat {
    for (final room in {
      ...from.chatTextScales.keys,
      ...to.chatTextScales.keys,
    }) {
      if (from.chatTextScale(room) != to.chatTextScale(room)) return room;
    }
    return null;
  }

  /// For the study log: `{id: [from, to]}` per changed value.
  Map<String, Object?> toJson() => {
    ...to.diff(from),
    if (changesTheme) 'theme': [themeFrom?.name, themeTo?.name],
  };
}

/// A proposed settings change, always shown to the user before it applies.
/// It comes either from a heuristic or from the user's own request through
/// the on-device model.
class Suggestion {
  /// The heuristic id, or the function the model called for a request
  /// through the model. Rate limits and opt-outs are kept per id.
  final String id;

  /// Premade text per language code.
  final Map<String, String> descriptions;

  /// How long the same id stays quiet after the user declines.
  final Duration cooldown;

  final SettingsChange change;

  /// True when the user asked for this change, so heuristic rate limits do
  /// not apply.
  final bool isUserRequest;

  const Suggestion({
    required this.id,
    required this.descriptions,
    required this.cooldown,
    required this.change,
    this.isUserRequest = false,
  });

  factory Suggestion.fromHeuristic(
    Heuristic heuristic, {
    required AccessibilitySettings settings,
    required double to,
  }) => Suggestion(
    id: heuristic.id,
    descriptions: heuristic.descriptions,
    cooldown: heuristic.cooldown,
    change: SettingsChange.scale(settings, heuristic.category, to),
  );

  /// A change the user asked for through the model, [function] being the
  /// function it called.
  factory Suggestion.userRequest(
    String function,
    SettingsChange change, {
    Map<String, String> descriptions = const {},
  }) => Suggestion(
    id: function,
    descriptions: descriptions,
    cooldown: Duration.zero,
    change: change,
    isUserRequest: true,
  );

  String description(String languageCode) =>
      descriptions[languageCode] ?? descriptions['en'] ?? '';
}
