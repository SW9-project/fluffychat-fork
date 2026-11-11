// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../accessibility_settings.dart';
import '../settings_registry.dart';
import 'assist_tools.dart';

/// One heuristic line from `assets/assist/heuristics.md`.
class HeuristicRule {
  final String id;
  final String category;
  final String text;

  const HeuristicRule(this.id, this.category, this.text);
}

/// The parsed `assets/assist/heuristics.md`: the system prompt and the
/// heuristics per category. The team edits that file; see its header for the
/// format.
class AssistPromptTemplate {
  static const assetPath = 'assets/assist/heuristics.md';

  final String system;
  final Map<String, List<HeuristicRule>> categories;

  const AssistPromptTemplate({required this.system, required this.categories});

  static Future<AssistPromptTemplate> load([AssetBundle? bundle]) async =>
      parse(await (bundle ?? rootBundle).loadString(assetPath));

  static final _comment = RegExp(r'<!--.*?-->', dotAll: true);
  static final _rule = RegExp(r'^-\s*([A-Za-z0-9-]+)\s*:\s*(.+)$');

  /// Parses the markdown. Lines that do not fit the format are ignored, so a
  /// stray note does not break the assistant.
  static AssistPromptTemplate parse(String markdown) {
    final lines = markdown.replaceAll(_comment, '').split(RegExp(r'\r?\n'));
    final system = <String>[];
    final categories = <String, List<HeuristicRule>>{};
    String? section;
    String? category;
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.startsWith('# ')) {
        section = line.substring(2).trim().toLowerCase();
        category = null;
        continue;
      }
      if (section == 'system') {
        system.add(line);
      } else if (section == 'heuristics') {
        if (line.startsWith('## ')) {
          category = line.substring(3).trim().toLowerCase();
          categories.putIfAbsent(category, () => []);
        } else if (category != null) {
          final match = _rule.firstMatch(line.trim());
          if (match != null) {
            categories[category]!.add(
              HeuristicRule(match[1]!, category, match[2]!.trim()),
            );
          }
        }
      }
    }
    return AssistPromptTemplate(
      system: system.join('\n').trim(),
      categories: categories,
    );
  }

  /// Heuristics in [names], in file order, without duplicates.
  List<HeuristicRule> rulesIn(Iterable<String> names) {
    final seen = <String>{};
    return [
      for (final name in names)
        for (final rule in categories[name] ?? const <HeuristicRule>[])
          if (seen.add(rule.id)) rule,
    ];
  }

  HeuristicRule? ruleById(String id) {
    for (final rules in categories.values) {
      for (final rule in rules) {
        if (rule.id == id) return rule;
      }
    }
    return null;
  }
}

/// Everything sent to the online model for one prompt.
class AssistPrompt {
  final String system;
  final List<AssistTool> tools;

  const AssistPrompt({required this.system, required this.tools});

  /// About four characters per token, the same estimate as the proxy.
  static int estimateTokens(String text) => (text.length / 4).ceil();
}

/// Builds the system prompt and tools for a request.
abstract final class AssistPromptBuilder {
  /// Free tiers cap tokens per minute and per day, so a request (system
  /// prompt, tools, settings and the user's words) should stay below this.
  static const tokenBudget = 2500;

  /// [settingIds] limits the tools offered, and with them the heuristic
  /// categories included. By default every registered setting is offered.
  static AssistPrompt build(
    AssistPromptTemplate template,
    AccessibilitySettings settings, {
    Iterable<String>? settingIds,
  }) {
    final offered = [
      for (final setting in SettingsRegistry.all)
        if (settingIds == null || settingIds.contains(setting.id)) setting,
    ];
    final tools = AssistTools.build(template, offered);
    final categories = {
      for (final tool in tools) ...tool.setting.heuristicCategories,
    };
    final heuristics = template.rulesIn(
      template.categories.keys.where(categories.contains),
    );
    final current = SettingsRegistry.currentValues(settings);
    final system = [
      template.system,
      '',
      'Heuristics (use the id in the "heuristic" parameter):',
      for (final rule in heuristics) '- ${rule.id}: ${rule.text}',
      '',
      'Current settings (1.0 is normal):',
      for (final tool in tools)
        '- ${tool.setting.id}: ${current[tool.setting.id]}',
    ].join('\n');
    return AssistPrompt(system: system, tools: tools);
  }

  /// Logs a warning in debug builds when the request is likely over
  /// [tokenBudget]. The warning carries only sizes, never the text.
  static int checkBudget(int estimatedTokens) {
    if (kDebugMode && estimatedTokens > tokenBudget) {
      Logs().w(
        'Assist request is about $estimatedTokens tokens, over the budget of '
        '$tokenBudget. Shorten assets/assist/heuristics.md or offer fewer tools.',
      );
    }
    return estimatedTokens;
  }
}
