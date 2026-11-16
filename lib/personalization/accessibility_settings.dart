// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a setting is shown on the Accessibility page.
enum ScaleGroup { general, text, buttons }

/// The UI element categories a user can resize.
///
/// This is the single source of truth for which sizes exist and which values
/// they accept. The model's functions (`assets/personalization_tools.json`)
/// are mapped onto these in `ToolCallInterpreter`.
enum ScaleCategory {
  text('text_scale', min: 0.8, max: 2.0, step: 0.1),

  /// Text in message bubbles, on top of [text].
  messageText(
    'message_text_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.text,
  ),

  /// Chat names and previews in the chat list, on top of [text].
  chatListText(
    'chat_list_text_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.text,
  ),

  /// Titles at the top of the screen, on top of [text].
  titleText(
    'title_text_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.text,
  ),

  /// Text typed in the message input, on top of [text].
  inputText(
    'input_text_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.text,
  ),
  button('button_scale', min: 1.0, max: 2.0, step: 0.1),

  /// One button, on top of [button].
  sendButton(
    'send_button_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.buttons,
  ),
  attachButton(
    'attach_button_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.buttons,
  ),
  emojiButton(
    'emoji_button_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.buttons,
  ),
  microphoneButton(
    'microphone_button_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.buttons,
  ),
  backButton(
    'back_button_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.buttons,
  ),
  searchButton(
    'search_button_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.buttons,
  ),
  menuButton(
    'menu_button_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.buttons,
  ),
  navigationButton(
    'navigation_button_scale',
    min: 0.8,
    max: 2.0,
    step: 0.1,
    group: ScaleGroup.buttons,
  ),
  touchTarget('touch_target_scale', min: 1.0, max: 2.0, step: 0.1),

  /// Space between controls that can be tapped.
  spacing('spacing_scale', min: 0.5, max: 2.0, step: 0.25),
  avatar('avatar_scale', min: 1.0, max: 2.0, step: 0.1);

  const ScaleCategory(
    this.id, {
    required this.min,
    required this.max,
    required this.step,
    this.group = ScaleGroup.general,
  });

  final String id;
  final double min;
  final double max;
  final double step;
  final ScaleGroup group;

  double get defaultValue => 1.0;

  /// The size this one is on top of: the text size for one text, the button
  /// size for one button.
  ScaleCategory? get parent => switch (group) {
    ScaleGroup.general => null,
    ScaleGroup.text => ScaleCategory.text,
    ScaleGroup.buttons => ScaleCategory.button,
  };

  String get storageKey => 'personalization.$id';

  /// How much one step of a suggestion changes this size, from the
  /// assistant or from a heuristic. Coarser than the slider's own [step], so
  /// one suggestion makes a visible difference.
  double get suggestionStep => step > 0.2 ? step : 0.2;

  int get divisions => ((max - min) / step).round();

  bool allows(double value) => value >= min && value <= max;

  /// Clamps [value] to the range and snaps it to the nearest step. Without
  /// [snap] it is only rounded, so a size on top of another can match a step
  /// of the whole size.
  double normalize(double value, {bool snap = true}) {
    if (!snap) {
      // A size on top of another may go further, so its whole size can reach
      // every step of [min] to [max] whatever the size below it is.
      final p = parent;
      final lo = p == null ? min : min / p.max;
      final hi = p == null ? max : max / p.min;
      return double.parse(value.clamp(lo, hi).toStringAsFixed(3));
    }
    final steps = ((value.clamp(min, max) - min) / step).round();
    // Rounding avoids floating point noise such as 1.2000000000000002.
    return double.parse(
      (min + steps * step).clamp(min, max).toStringAsFixed(2),
    );
  }

  static Iterable<ScaleCategory> inGroup(ScaleGroup group) =>
      values.where((c) => c.group == group);
}

/// The buttons that can be resized one by one. Each has its own
/// [ScaleCategory] on top of [ScaleCategory.button].
enum AccessibleButton {
  send(ScaleCategory.sendButton),
  attach(ScaleCategory.attachButton),
  emoji(ScaleCategory.emojiButton),
  microphone(ScaleCategory.microphoneButton),
  back(ScaleCategory.backButton),
  search(ScaleCategory.searchButton),
  menu(ScaleCategory.menuButton),
  navigation(ScaleCategory.navigationButton);

  const AccessibleButton(this.category);

  final ScaleCategory category;
}

/// The settings that are on or off.
enum AccessibilityToggle {
  /// Words next to button icons.
  buttonLabels('button_labels'),

  /// Stronger colors and bold text.
  highContrast('high_contrast');

  const AccessibilityToggle(this.id);

  final String id;

  String get storageKey => 'personalization.$id';
}

@immutable
class AccessibilitySettings {
  final Map<ScaleCategory, double> _values;
  final Set<AccessibilityToggle> _enabled;

  /// Text scale per chat, by room id, on top of the other text scales. A chat
  /// without an entry uses 1.0.
  final Map<String, double> _chatText;

  const AccessibilitySettings._(this._values, this._enabled, this._chatText);

  static const AccessibilitySettings defaults = AccessibilitySettings._(
    {},
    {},
    {},
  );

  /// The range and step of a chat's own text scale.
  static const ScaleCategory chatTextRange = ScaleCategory.messageText;

  static const String chatTextKey = 'personalization.chat_text_scales';

  /// Touch targets never get smaller than the Android minimum.
  static const double minTouchTarget = 48.0;

  double operator [](ScaleCategory category) =>
      _values[category] ?? category.defaultValue;

  bool isOn(AccessibilityToggle toggle) => _enabled.contains(toggle);

  double get textScale => this[ScaleCategory.text];

  /// These four apply on top of [textScale], see [onTop].
  double get messageTextScale => onTop(ScaleCategory.messageText);
  double get chatListTextScale => onTop(ScaleCategory.chatListText);
  double get titleTextScale => onTop(ScaleCategory.titleText);
  double get inputTextScale => onTop(ScaleCategory.inputText);
  double get buttonScale => this[ScaleCategory.button];
  double get touchTargetScale => this[ScaleCategory.touchTarget];
  double get spacingScale => this[ScaleCategory.spacing];
  double get avatarScale => this[ScaleCategory.avatar];
  bool get buttonLabels => isOn(AccessibilityToggle.buttonLabels);
  bool get highContrast => isOn(AccessibilityToggle.highContrast);

  /// The text scale of the chat with [roomId], on top of the others.
  double chatTextScale(String? roomId) =>
      roomId == null ? 1.0 : _chatText[roomId] ?? 1.0;

  /// The whole text scale of messages in the chat with [roomId].
  /// Never outside the range of [chatTextRange].
  double messageScale(String? roomId) => _round(
    (effective(ScaleCategory.messageText) * chatTextScale(roomId)).clamp(
      chatTextRange.min,
      chatTextRange.max,
    ),
  );

  /// Chats that have their own text scale.
  Map<String, double> get chatTextScales => Map.unmodifiable(_chatText);

  static double _round(double value) => double.parse(value.toStringAsFixed(2));

  /// The whole size of [category], with its [ScaleCategory.parent] applied,
  /// and never outside the range of [category].
  double effective(ScaleCategory category) => switch (category.parent) {
    null => this[category],
    final parent => _round(
      (this[parent] * this[category]).clamp(category.min, category.max),
    ),
  };

  /// What [category] adds on top of its parent, so both together are
  /// [effective].
  double onTop(ScaleCategory category) => switch (category.parent) {
    null => this[category],
    final parent => effective(category) / this[parent],
  };

  /// These settings with the whole size of [category] at [value]. Only
  /// [category] changes, not its parent.
  AccessibilitySettings withEffective(ScaleCategory category, double value) =>
      switch (category.parent) {
        null => copyWith(category, value),
        final parent => copyWith(
          category,
          value.clamp(category.min, category.max) / this[parent],
          snap: false,
        ),
      };

  AccessibilitySettings copyWith(
    ScaleCategory category,
    double value, {
    bool snap = true,
  }) => AccessibilitySettings._(
    {..._values, category: category.normalize(value, snap: snap)},
    _enabled,
    _chatText,
  );

  AccessibilitySettings withToggle(AccessibilityToggle toggle, bool on) =>
      AccessibilitySettings._(
        _values,
        on ? {..._enabled, toggle} : (_enabled.toSet()..remove(toggle)),
        _chatText,
      );

  /// A chat's own text scale. 1.0 removes the entry. Not snapped, so the
  /// whole message size can match a step.
  AccessibilitySettings withChatText(String roomId, double value) {
    final normalized = chatTextRange.normalize(value, snap: false);
    final chats = {..._chatText};
    if (normalized == 1.0) {
      chats.remove(roomId);
    } else {
      chats[roomId] = normalized;
    }
    return AccessibilitySettings._(_values, _enabled, chats);
  }

  /// These settings with [category] back at its default.
  AccessibilitySettings without(ScaleCategory category) =>
      copyWith(category, category.defaultValue);

  /// These settings without any chat's own text scale.
  AccessibilitySettings withoutChatText() =>
      AccessibilitySettings._(_values, _enabled, const {});

  /// Icon size for a button whose icon is [base] at scale 1. With [button],
  /// that button's own scale applies on top.
  double icon([double base = 24.0, AccessibleButton? button]) =>
      base * buttonScale * (button == null ? 1.0 : onTop(button.category));

  double avatar(double base) => base * avatarScale;

  double touchTarget(double base) =>
      max(minTouchTarget, base * touchTargetScale);

  /// Space between tappable controls whose space is [base] at scale 1.
  double spacing(double base) => base * spacingScale;

  /// Side length of a box holding an icon button: large enough for the touch
  /// target and for the scaled icon plus the button's padding.
  double buttonBox(double base, [AccessibleButton? button]) =>
      max(touchTarget(base), icon(24, button) + 16);

  /// Reads the stored settings. Until our own text scale has been stored, the
  /// old chat-only `fontSizeFactor` from FluffyChat is used as text scale.
  static AccessibilitySettings load(SharedPreferences store) {
    var settings = defaults;
    if (!store.containsKey(ScaleCategory.text.storageKey)) {
      final old = store.get(AppSettings.fontSizeFactor.key);
      if (old is double) settings = settings.copyWith(ScaleCategory.text, old);
    }
    for (final category in ScaleCategory.values) {
      final value = store.get(category.storageKey);
      if (value is double) {
        settings = settings.copyWith(category, value, snap: false);
      }
    }
    for (final toggle in AccessibilityToggle.values) {
      if (store.get(toggle.storageKey) == true) {
        settings = settings.withToggle(toggle, true);
      }
    }
    final chats = store.get(chatTextKey);
    if (chats is String) {
      try {
        final json = jsonDecode(chats);
        if (json is Map) {
          for (final MapEntry(:key, :value) in json.entries) {
            if (key is String && value is num) {
              settings = settings.withChatText(key, value.toDouble());
            }
          }
        }
      } on FormatException {
        // A broken entry is dropped; the chats use the normal size.
      }
    }
    return settings;
  }

  static bool isStored(SharedPreferences store) =>
      store.containsKey(ScaleCategory.text.storageKey);

  Future<void> save(SharedPreferences store) async {
    for (final category in ScaleCategory.values) {
      await store.setDouble(category.storageKey, this[category]);
    }
    for (final toggle in AccessibilityToggle.values) {
      await store.setBool(toggle.storageKey, isOn(toggle));
    }
    await store.setString(chatTextKey, jsonEncode(_chatText));
  }

  /// What differs from [other], as `{id: [other's value, this value]}`, for
  /// the study log. Chats are never named: a changed chat text scale is
  /// logged as `chat_text_scale`, and several as a list of pairs.
  Map<String, List<Object?>> diff(AccessibilitySettings other) {
    final chats = [
      for (final room in {..._chatText.keys, ...other._chatText.keys})
        if (chatTextScale(room) != other.chatTextScale(room))
          [other.chatTextScale(room), chatTextScale(room)],
    ];
    return {
      for (final c in ScaleCategory.values)
        if (this[c] != other[c]) c.id: [other[c], this[c]],
      for (final t in AccessibilityToggle.values)
        if (isOn(t) != other.isOn(t)) t.id: [other.isOn(t), isOn(t)],
      if (chats.length == 1) 'chat_text_scale': chats.single,
      if (chats.length > 1) 'chat_text_scales': chats,
    };
  }

  static const _mapEquality = MapEquality<String, double>();

  @override
  bool operator ==(Object other) =>
      other is AccessibilitySettings &&
      ScaleCategory.values.every((c) => this[c] == other[c]) &&
      AccessibilityToggle.values.every((t) => isOn(t) == other.isOn(t)) &&
      _mapEquality.equals(_chatText, other._chatText);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ScaleCategory.values.map((c) => this[c])),
    Object.hashAll(AccessibilityToggle.values.map(isOn)),
    _mapEquality.hash(_chatText),
  );

  @override
  String toString() =>
      'AccessibilitySettings(${ScaleCategory.values.map((c) => '${c.id}: ${this[c]}').join(', ')}, '
      '${AccessibilityToggle.values.map((t) => '${t.id}: ${isOn(t)}').join(', ')}, '
      'chats: $_chatText)';
}
