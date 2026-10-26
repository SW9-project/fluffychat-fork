// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The UI element categories a user can resize.
///
/// This is the single source of truth for which settings exist and which
/// values they accept. Phase 3 builds the model's allowlist from it.
enum ScaleCategory {
  text('text_scale', min: 0.8, max: 2.0, step: 0.1),
  button('button_scale', min: 1.0, max: 2.0, step: 0.1),
  touchTarget('touch_target_scale', min: 1.0, max: 2.0, step: 0.1),
  avatar('avatar_scale', min: 1.0, max: 2.0, step: 0.1);

  const ScaleCategory(
    this.id, {
    required this.min,
    required this.max,
    required this.step,
  });

  final String id;
  final double min;
  final double max;
  final double step;

  double get defaultValue => 1.0;

  String get storageKey => 'personalization.$id';

  int get divisions => ((max - min) / step).round();

  bool allows(double value) => value >= min && value <= max;

  /// Clamps [value] to the range and snaps it to the nearest step.
  double normalize(double value) {
    final steps = ((value.clamp(min, max) - min) / step).round();
    // Rounding avoids floating point noise such as 1.2000000000000002.
    return double.parse(
      (min + steps * step).clamp(min, max).toStringAsFixed(2),
    );
  }
}

@immutable
class AccessibilitySettings {
  final Map<ScaleCategory, double> _values;

  const AccessibilitySettings._(this._values);

  static const AccessibilitySettings defaults = AccessibilitySettings._({});

  /// Touch targets never get smaller than the Android minimum.
  static const double minTouchTarget = 48.0;

  double operator [](ScaleCategory category) =>
      _values[category] ?? category.defaultValue;

  double get textScale => this[ScaleCategory.text];
  double get buttonScale => this[ScaleCategory.button];
  double get touchTargetScale => this[ScaleCategory.touchTarget];
  double get avatarScale => this[ScaleCategory.avatar];

  AccessibilitySettings copyWith(ScaleCategory category, double value) =>
      AccessibilitySettings._({
        ..._values,
        category: category.normalize(value),
      });

  /// Icon size for a button whose icon is [base] at scale 1.
  double icon([double base = 24.0]) => base * buttonScale;

  double avatar(double base) => base * avatarScale;

  double touchTarget(double base) =>
      max(minTouchTarget, base * touchTargetScale);

  /// Side length of a box holding an icon button: large enough for the touch
  /// target and for the scaled icon plus the button's padding.
  double buttonBox(double base) => max(touchTarget(base), icon() + 16);

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
      if (value is double) settings = settings.copyWith(category, value);
    }
    return settings;
  }

  static bool isStored(SharedPreferences store) =>
      store.containsKey(ScaleCategory.text.storageKey);

  Future<void> save(SharedPreferences store) async {
    for (final category in ScaleCategory.values) {
      await store.setDouble(category.storageKey, this[category]);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AccessibilitySettings &&
      ScaleCategory.values.every((c) => this[c] == other[c]);

  @override
  int get hashCode => Object.hashAll(ScaleCategory.values.map((c) => this[c]));

  @override
  String toString() =>
      'AccessibilitySettings(${ScaleCategory.values.map((c) => '${c.id}: ${this[c]}').join(', ')})';
}
