// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';

import 'accessibility_settings.dart';

/// Every accessibility setting the Assist widget may propose a change to.
///
/// This is the single source of truth for the online assistant: the tool
/// schemas it is offered (`assist/assist_tools.dart`), the validator that
/// checks its answers (`assist/assist_validator.dart`) and the setting values
/// sent with each request are all built from [SettingsRegistry.all], so the
/// tools can never drift from the settings the app really has. Ranges and
/// defaults are read from [ScaleCategory], never repeated here.
///
/// ## Adding a setting
///
/// 1. Add the setting where it is stored and applied. For a size, add a value
///    to [ScaleCategory] (id, min, max, step) and read it in the widgets that
///    should change; the Accessibility settings page picks it up on its own.
/// 2. Add one entry to [SettingsRegistry.all]: a [modelDescription] in plain
///    English that tells the model what the setting changes and when it
///    helps, and the [heuristicCategories] it belongs to.
/// 3. Make sure each of those categories has at least one heuristic in
///    `assets/assist/heuristics.md`. A setting without any heuristic is not
///    offered, because every tool call must name the heuristic behind it.
/// 4. Add the setting's title to `categoryTitles` in
///    `personalization_l10n.dart` (English and Danish) and a sample to
///    `assist/change_preview.dart`.
/// 5. Refresh the evaluation fixture in `llm-proxy/eval/fixtures/` with
///    `UPDATE_ASSIST_FIXTURE=1 flutter test test/personalization/assist_eval_fixture_test.dart`,
///    then run `flutter test test/personalization` (a test fails while the
///    fixture is stale).
///
/// Only number settings exist so far. A yes/no or choice setting needs a new
/// subclass of [SettingDefinition] with its own value schema, a case in the
/// validator and a way to apply and undo it.
sealed class SettingDefinition {
  const SettingDefinition();

  /// Stable id, used in tool names, requests and the study log.
  String get id;

  /// What the setting changes and when it helps, for the model.
  String get modelDescription;

  /// Which sections of `heuristics.md` justify changing this setting.
  List<String> get heuristicCategories;

  /// JSON Schema of the `value` parameter.
  Map<String, Object?> get valueSchema;

  /// The current value, as sent to the model.
  Object currentValue(AccessibilitySettings settings);
}

/// A size factor from [ScaleCategory]; 1.0 is the normal size.
class NumberSetting extends SettingDefinition {
  final ScaleCategory category;

  @override
  final String modelDescription;

  @override
  final List<String> heuristicCategories;

  const NumberSetting(
    this.category, {
    required this.modelDescription,
    required this.heuristicCategories,
  });

  @override
  String get id => category.id;

  double get min => category.min;
  double get max => category.max;
  double get step => category.step;
  double get defaultValue => category.defaultValue;

  @override
  Map<String, Object?> get valueSchema => {
    'type': 'number',
    'minimum': min,
    'maximum': max,
    'description':
        'The new size factor: $defaultValue is normal, from $min to $max '
        'in steps of $step.',
  };

  @override
  double currentValue(AccessibilitySettings settings) => settings[category];
}

abstract final class SettingsRegistry {
  static const List<SettingDefinition> all = [
    NumberSetting(
      ScaleCategory.text,
      modelDescription:
          'Size of all text in the app, such as messages and chat names. '
          'Bigger helps when text is hard to read.',
      heuristicCategories: ['readability', 'overview'],
    ),
    NumberSetting(
      ScaleCategory.inputText,
      modelDescription:
          'Size of the text the user types in the message box, on top of the '
          'text size. Bigger helps when it is hard to see what one types.',
      heuristicCategories: ['typing', 'overview'],
    ),
    NumberSetting(
      ScaleCategory.button,
      modelDescription:
          'Size of the icons on buttons, such as send, back and attach. '
          'Bigger helps when buttons are hard to see or hit.',
      heuristicCategories: ['target-size', 'overview'],
    ),
    NumberSetting(
      ScaleCategory.touchTarget,
      modelDescription:
          'Size of the area around a button that reacts to a tap. Bigger '
          'helps when taps miss buttons or the wrong thing gets pressed.',
      heuristicCategories: ['target-size', 'overview'],
    ),
    NumberSetting(
      ScaleCategory.avatar,
      modelDescription:
          'Size of profile pictures in the chat list and next to messages. '
          'Bigger helps when it is hard to see who wrote.',
      heuristicCategories: ['recognition', 'overview'],
    ),
  ];

  static SettingDefinition? byId(String id) =>
      all.firstWhereOrNull((s) => s.id == id);

  /// The current value of every registered setting, keyed by id. Nothing
  /// else about the user or the app is ever added here.
  static Map<String, Object> currentValues(AccessibilitySettings settings) => {
    for (final setting in all) setting.id: setting.currentValue(settings),
  };
}
