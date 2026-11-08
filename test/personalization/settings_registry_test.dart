// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/settings_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsRegistry', () {
    test('has exactly one entry per ScaleCategory', () {
      final categories = SettingsRegistry.all
          .whereType<NumberSetting>()
          .map((s) => s.category)
          .toList();
      expect(categories, unorderedEquals(ScaleCategory.values));
      expect(categories.toSet().length, categories.length);
    });

    test('ids are unique and usable in tool names', () {
      final ids = SettingsRegistry.all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z][a-z0-9_]{0,50}$')));
      }
    });

    test('ranges come from ScaleCategory', () {
      for (final setting in SettingsRegistry.all.cast<NumberSetting>()) {
        expect(setting.min, setting.category.min);
        expect(setting.max, setting.category.max);
        expect(setting.step, setting.category.step);
        expect(setting.valueSchema['minimum'], setting.category.min);
        expect(setting.valueSchema['maximum'], setting.category.max);
      }
    });

    test('every setting has a description and at least one category', () {
      for (final setting in SettingsRegistry.all) {
        expect(setting.modelDescription.trim(), isNotEmpty);
        expect(setting.heuristicCategories, isNotEmpty);
      }
    });

    test('current values contain only the registered settings', () {
      final settings = AccessibilitySettings.defaults
          .copyWith(ScaleCategory.button, 1.4)
          .copyWith(ScaleCategory.text, 1.2);
      final values = SettingsRegistry.currentValues(settings);
      expect(values.keys, SettingsRegistry.all.map((s) => s.id));
      expect(values['button_scale'], 1.4);
      expect(values['text_scale'], 1.2);
      expect(values['avatar_scale'], 1.0);
    });

    test('byId finds settings and rejects unknown ids', () {
      expect(SettingsRegistry.byId('text_scale'), isA<NumberSetting>());
      expect(SettingsRegistry.byId('screen_reader'), isNull);
    });
  });
}
