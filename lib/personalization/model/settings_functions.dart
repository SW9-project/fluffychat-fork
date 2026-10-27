// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';

import '../accessibility_settings.dart';

/// A function the model may call, with its parameters as a JSON Schema
/// object. Independent of any inference package, so the model can be
/// swapped.
class FunctionDeclaration {
  final String name;
  final String description;
  final Map<String, Object?> parameters;

  const FunctionDeclaration({
    required this.name,
    required this.description,
    required this.parameters,
  });
}

/// Builds the functions offered to the model from [ScaleCategory], the one
/// definition of which settings exist and which values they accept. The model
/// can therefore never be offered a setting the app does not have.
///
/// Every function is relative (`bigger` or `smaller`, 1 to [maxSteps] steps),
/// because complaints like "the buttons are too small" say which way, not
/// which value, and the model does not know the current value.
abstract final class SettingsFunctions {
  static const directionParam = 'direction';
  static const stepsParam = 'steps';
  static const bigger = 'bigger';
  static const smaller = 'smaller';
  static const maxSteps = 3;

  static String nameFor(ScaleCategory category) =>
      'adjust_${category.id.replaceAll('_scale', '_size')}';

  static ScaleCategory? categoryFor(String functionName) =>
      ScaleCategory.values.firstWhereOrNull((c) => nameFor(c) == functionName);

  static final List<FunctionDeclaration> all = [
    for (final category in ScaleCategory.values) _declarationFor(category),
  ];

  static const Map<ScaleCategory, String> _purposes = {
    ScaleCategory.text:
        'Make all text in the app bigger or smaller, for example when '
        'messages are hard to read. The text the user types follows it.',
    ScaleCategory.inputText:
        'Make the text the user types in the message box bigger or smaller.',
    ScaleCategory.button:
        'Make the icons on buttons bigger or smaller, for example when '
        'buttons are hard to see.',
    ScaleCategory.touchTarget:
        'Make the area that reacts to a tap bigger or smaller, for example '
        'when taps miss the buttons or the wrong thing gets pressed.',
    ScaleCategory.avatar:
        'Make profile pictures bigger or smaller, for example when it is hard '
        'to see who wrote.',
  };

  static FunctionDeclaration _declarationFor(ScaleCategory category) =>
      FunctionDeclaration(
        name: nameFor(category),
        description:
            '${_purposes[category]} The size goes from '
            '${category.min} to ${category.max} times normal, '
            'in steps of ${category.step}.',
        parameters: {
          'type': 'object',
          'properties': {
            directionParam: {
              'type': 'string',
              'enum': [bigger, smaller],
              'description': 'Whether it should become bigger or smaller.',
            },
            stepsParam: {
              'type': 'integer',
              'minimum': 1,
              'maximum': maxSteps,
              'description':
                  'How much: 1 is a little, 2 is more, $maxSteps is a lot. '
                  'Use 1 when unsure.',
            },
          },
          'required': [directionParam],
        },
      );
}
