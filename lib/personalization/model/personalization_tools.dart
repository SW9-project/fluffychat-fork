// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/services.dart';

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

/// The functions the fine-tuned model was trained on, read from
/// `assets/personalization_tools.json` (see `docs/personalization-tools.md`).
///
/// The model learned these exact words, so the app sends the file's
/// functions, in its order, and never builds functions of its own. They are
/// shaped like the training prompts (see [_forModel]): `default`, `minimum`
/// and `maximum` are left out, because FunctionGemma's chat template drops
/// them, and the app reads them from the file instead.
class PersonalizationTools {
  static const asset = 'assets/personalization_tools.json';

  static const changeTextSize = 'change_text_size';
  static const changeButtonSize = 'change_button_size';
  static const changeSpacing = 'change_spacing';
  static const changeLineSpacing = 'change_line_spacing';
  static const setSimpleMode = 'set_simple_mode';
  static const setButtonLabels = 'set_button_labels';
  static const setHighContrast = 'set_high_contrast';
  static const changeAvatarSize = 'change_avatar_size';
  static const setTheme = 'set_theme';
  static const setReadAloud = 'set_read_aloud';
  static const setBubbleColor = 'set_bubble_color';
  static const setAppColor = 'set_app_color';
  static const setWallpaper = 'set_wallpaper';
  static const setGesture = 'set_gesture';
  static const pinChat = 'pin_chat';
  static const muteChat = 'mute_chat';
  static const resetSettings = 'reset_settings';
  static const askClarification = 'ask_clarification';
  static const noAction = 'no_action';

  /// The functions [askClarification] can offer, in declaration order.
  static const changeFunctions = [
    changeTextSize,
    changeButtonSize,
    changeSpacing,
    changeLineSpacing,
    setSimpleMode,
    setButtonLabels,
    setHighContrast,
    changeAvatarSize,
    setTheme,
    setReadAloud,
    setBubbleColor,
    setAppColor,
    setWallpaper,
    setGesture,
    resetSettings,
  ];

  /// The words `size` may be, from smallest to biggest.
  static const sizeWords = ['small', 'medium', 'big', 'very_big'];

  /// The colors of `set_bubble_color` and `set_app_color`.
  static const colors = [
    'default',
    'red',
    'pink',
    'purple',
    'indigo',
    'blue',
    'cyan',
    'teal',
    'green',
    'lime',
    'yellow',
    'amber',
    'orange',
    'brown',
    'grey',
  ];

  /// The declarations as the model gets them.
  final List<FunctionDeclaration> declarations;

  /// The full declarations from the file, with ranges and defaults.
  final Map<String, Map<String, Object?>> _schemas;

  PersonalizationTools._(this.declarations, this._schemas);

  static Future<PersonalizationTools> load([AssetBundle? bundle]) async =>
      PersonalizationTools.fromJson(
        jsonDecode(await (bundle ?? rootBundle).loadString(asset))
            as Map<String, Object?>,
      );

  factory PersonalizationTools.fromJson(Map<String, Object?> json) {
    final declarations = <FunctionDeclaration>[];
    final schemas = <String, Map<String, Object?>>{};
    for (final entry in json['functions'] as List) {
      final function = entry as Map<String, Object?>;
      final name = function['name'] as String;
      final parameters = function['parameters'] as Map<String, Object?>;
      schemas[name] = parameters;
      declarations.add(
        FunctionDeclaration(
          name: name,
          description: function['description'] as String,
          parameters: _forModel(parameters) as Map<String, Object?>,
        ),
      );
    }
    return PersonalizationTools._(declarations, schemas);
  }

  static const _notForModel = {'default', 'minimum', 'maximum'};

  /// [value] as the training prompts had it. FunctionGemma's chat template
  /// sorts every object's keys and leaves out an empty `properties` or
  /// `required`, while LiteRT-LM writes the keys in the order it gets them
  /// and writes empty ones too. So the app sorts and drops them itself: the
  /// phone then renders the same prompt the model learned, which
  /// integration_test/personalization_model_test.dart checks. Lists, such as
  /// enum values, keep their order.
  static Object? _forModel(Object? value) => switch (value) {
    Map() => {
      for (final key in value.keys.cast<String>().toList()..sort())
        if (!_notForModel.contains(key) && !_isEmptyListing(key, value[key]))
          key: _forModel(value[key]),
    },
    List() => [for (final item in value) _forModel(item)],
    _ => value,
  };

  static bool _isEmptyListing(String key, Object? value) =>
      (key == 'properties' && value is Map && value.isEmpty) ||
      (key == 'required' && value is List && value.isEmpty);

  bool declares(String name) => _schemas.containsKey(name);

  Map<String, Object?> _property(String function, String parameter) =>
      ((_schemas[function]?['properties'] as Map?)?[parameter] as Map?)
          ?.cast<String, Object?>() ??
      const {};

  /// The declared default of [parameter], if any.
  Object? defaultOf(String function, String parameter) =>
      _property(function, parameter)['default'];

  /// The declared string values of [parameter], or null when it has none.
  List<String>? enumOf(String function, String parameter) {
    final property = _property(function, parameter);
    final values =
        (property['enum'] ?? (property['items'] as Map?)?['enum']) as List?;
    return values?.cast<String>();
  }

  /// The declared range of an integer [parameter].
  (int, int)? rangeOf(String function, String parameter) {
    final property = _property(function, parameter);
    final min = property['minimum'];
    final max = property['maximum'];
    if (min is! num || max is! num) return null;
    return (min.toInt(), max.toInt());
  }

  List<String> requiredOf(String function) =>
      ((_schemas[function]?['required'] as List?) ?? const []).cast<String>();
}
