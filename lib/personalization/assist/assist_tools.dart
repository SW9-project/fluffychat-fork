// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';

import '../settings_registry.dart';
import 'assist_prompt.dart';

/// One tool offered to the online model, generated from a [SettingDefinition]
/// so it can never ask for a setting the app does not have.
class AssistTool {
  static const valueParam = 'value';
  static const heuristicParam = 'heuristic';
  static const rationaleParam = 'rationale';
  static const rationaleMaxLength = 200;

  final SettingDefinition setting;

  /// The heuristics from the setting's categories; the model must name one.
  final List<String> heuristicIds;

  const AssistTool(this.setting, this.heuristicIds);

  String get name => nameFor(setting);

  static String nameFor(SettingDefinition setting) => 'set_${setting.id}';

  String get description {
    final s = setting;
    return switch (s) {
      NumberSetting() =>
        '${s.modelDescription} Normal is ${s.defaultValue}; allowed from '
            '${s.min} to ${s.max} in steps of ${s.step}.',
    };
  }

  /// The tool in the OpenAI chat-completions format.
  Map<String, Object?> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': {
          valueParam: setting.valueSchema,
          heuristicParam: {
            'type': 'string',
            'enum': heuristicIds,
            'description': 'Id of the heuristic that justifies the change.',
          },
          rationaleParam: {
            'type': 'string',
            'maxLength': rationaleMaxLength,
            'description':
                'One short, plain sentence in the user\'s language that tells '
                'the user why this change helps.',
          },
        },
        'required': [valueParam, heuristicParam, rationaleParam],
        'additionalProperties': false,
      },
    },
  };
}

abstract final class AssistTools {
  /// One tool per setting in [settings]. A setting with no heuristic in its
  /// categories is left out, because a call has to name one.
  static List<AssistTool> build(
    AssistPromptTemplate template, [
    List<SettingDefinition> settings = SettingsRegistry.all,
  ]) => [
    for (final setting in settings)
      if (template.rulesIn(setting.heuristicCategories) case final rules
          when rules.isNotEmpty)
        AssistTool(setting, [for (final r in rules) r.id]),
  ];

  static AssistTool? byName(List<AssistTool> tools, String name) =>
      tools.firstWhereOrNull((t) => t.name == name);
}
