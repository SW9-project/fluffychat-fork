// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:collection/collection.dart';

import '../accessibility_settings.dart';
import '../heuristics/heuristic.dart';
import '../model/settings_call_validator.dart';
import '../settings_registry.dart';
import 'assist_prompt.dart';
import 'assist_result.dart';
import 'assist_tools.dart';

/// A tool call as the online model returned it. [arguments] is the JSON
/// string from the API, or an already decoded map.
class AssistToolCall {
  final String name;
  final Object? arguments;

  const AssistToolCall(this.name, this.arguments);
}

/// Checks the online model's tool calls before anything is shown.
///
/// - Unknown tools and settings are rejected.
/// - The heuristic must be one offered for that tool.
/// - Values outside the range are clamped and snapped to the step, and the
///   proposal is marked [AssistProposal.clamped].
/// - The rationale is cleaned up and shortened; without one, the premade
///   description is shown instead.
/// - Only the first acceptable call is used: one change at a time.
///
/// It never throws. Anything unusable becomes an [AssistNoSuggestion], which
/// the tab shows as a friendly message.
abstract final class AssistValidator {
  static AssistResult validate(
    List<AssistToolCall> calls, {
    required List<AssistTool> tools,
    required AssistPromptTemplate template,
    required List<Heuristic> heuristics,
    required AccessibilitySettings settings,
  }) {
    if (calls.isEmpty) return const AssistNoSuggestion(RejectionReason.noCall);
    AssistResult? firstRejection;
    for (final call in calls) {
      final AssistResult result;
      try {
        result = _check(call, tools, template, heuristics, settings);
      } catch (_) {
        // Defensive: a malformed answer must never crash the tab.
        firstRejection ??= const AssistNoSuggestion(
          RejectionReason.invalidArguments,
        );
        continue;
      }
      if (result is AssistProposal) return result;
      firstRejection = _moreHelpful(firstRejection, result);
    }
    return firstRejection!;
  }

  /// An "already at the limit" answer tells the user more than "I didn't
  /// understand", so it wins when several calls are rejected.
  static AssistResult _moreHelpful(AssistResult? current, AssistResult next) {
    if (current == null) return next;
    int rank(AssistResult r) => switch (r) {
      AssistAtLimit() => 3,
      AssistNoSuggestion(reason: RejectionReason.noChange) => 2,
      AssistNoSuggestion(reason: RejectionReason.unknownFunction) => 0,
      _ => 1,
    };
    return rank(next) > rank(current) ? next : current;
  }

  static AssistResult _check(
    AssistToolCall call,
    List<AssistTool> tools,
    AssistPromptTemplate template,
    List<Heuristic> heuristics,
    AccessibilitySettings settings,
  ) {
    final tool = AssistTools.byName(tools, call.name.trim());
    if (tool == null) {
      return const AssistNoSuggestion(RejectionReason.unknownFunction);
    }
    final args = _arguments(call.arguments);
    if (args == null) {
      return const AssistNoSuggestion(RejectionReason.invalidArguments);
    }

    final heuristicId = args[AssistTool.heuristicParam];
    final rule =
        heuristicId is String && tool.heuristicIds.contains(heuristicId.trim())
        ? template.ruleById(heuristicId.trim())
        : null;
    if (rule == null) {
      return const AssistNoSuggestion(RejectionReason.unknownHeuristic);
    }

    switch (tool.setting) {
      case NumberSetting(:final category, :final min, :final max):
        final value = _number(args[AssistTool.valueParam]);
        if (value == null) {
          return const AssistNoSuggestion(RejectionReason.invalidArguments);
        }
        final from = settings[category];
        final to = category.normalize(value);
        final clamped = value < min - 1e-9 || value > max + 1e-9;
        final heuristic = _heuristicFor(rule, category, heuristics, from, to);
        if (to == from) {
          return to == min || to == max
              ? AssistAtLimit(heuristic, category)
              : const AssistNoSuggestion(RejectionReason.noChange);
        }
        return AssistProposal(
          heuristic,
          category,
          from,
          to,
          rationale: cleanRationale(args[AssistTool.rationaleParam]),
          clamped: clamped,
        );
    }
  }

  static Map<String, Object?>? _arguments(Object? raw) {
    var decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw.trim().isEmpty ? '{}' : raw);
      } on FormatException {
        return null;
      }
    }
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  static double? _number(Object? raw) {
    final number = switch (raw) {
      num() => raw.toDouble(),
      String() => double.tryParse(raw.trim()),
      _ => null,
    };
    if (number == null || !number.isFinite) return null;
    return number;
  }

  /// The heuristic from `personalization_heuristics.json` with the same id,
  /// so its premade descriptions can be shown; otherwise one built from the
  /// line in `heuristics.md`.
  static Heuristic _heuristicFor(
    HeuristicRule rule,
    ScaleCategory category,
    List<Heuristic> heuristics,
    double from,
    double to,
  ) {
    final known = heuristics.firstWhereOrNull((h) => h.id == rule.id);
    if (known != null && known.category == category) return known;
    return Heuristic(
      id: rule.id,
      source: AssistPromptTemplate.assetPath,
      category: category,
      steps: to < from ? -1 : 1,
      cooldown: const Duration(minutes: 30),
      descriptions: const {},
      rule: rule.text,
    );
  }

  static final _control = RegExp(r'[\u0000-\u001f\u007f]');
  static final _markup = RegExp(r'[*_`#>\[\]<]');
  static final _space = RegExp(r'\s+');

  /// The rationale as plain text of at most
  /// [AssistTool.rationaleMaxLength] characters, or null when there is none.
  static String? cleanRationale(Object? raw) {
    if (raw is! String) return null;
    var text = raw
        .replaceAll(_control, ' ')
        .replaceAll(_markup, '')
        .replaceAll(_space, ' ')
        .trim();
    if (text.isEmpty) return null;
    const max = AssistTool.rationaleMaxLength;
    if (text.length > max) {
      final cut = text.lastIndexOf(' ', max - 1);
      text =
          '${text.substring(0, cut > max ~/ 2 ? cut : max - 1).trimRight()}…';
    }
    return text;
  }
}
