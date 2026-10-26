// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/personalization/accessibility_controller.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _store([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('ScaleCategory', () {
    test('every category has a valid range that contains its default', () {
      for (final c in ScaleCategory.values) {
        expect(c.min, lessThan(c.max), reason: c.id);
        expect(c.step, greaterThan(0), reason: c.id);
        expect(c.allows(c.defaultValue), isTrue, reason: c.id);
        expect(c.divisions, greaterThan(0), reason: c.id);
      }
    });

    test('ids and storage keys are unique', () {
      final keys = ScaleCategory.values.map((c) => c.storageKey).toSet();
      expect(keys.length, ScaleCategory.values.length);
    });

    test('normalize clamps to range and snaps to step', () {
      const c = ScaleCategory.button;
      expect(c.normalize(5.0), c.max);
      expect(c.normalize(-1.0), c.min);
      expect(c.normalize(1.23), 1.2);
      expect(c.normalize(1.26), 1.3);
      expect(c.normalize(1.2000000000000002), 1.2);
    });

    test('allows rejects values outside the range', () {
      const c = ScaleCategory.avatar;
      expect(c.allows(c.max + 0.1), isFalse);
      expect(c.allows(c.min - 0.1), isFalse);
    });
  });

  group('AccessibilitySettings', () {
    test('defaults are 1.0 everywhere', () {
      for (final c in ScaleCategory.values) {
        expect(AccessibilitySettings.defaults[c], 1.0);
      }
    });

    test('copyWith normalizes and leaves other categories alone', () {
      final s = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.text,
        9.0,
      );
      expect(s.textScale, ScaleCategory.text.max);
      expect(s.buttonScale, 1.0);
    });

    test('equality is by value', () {
      final a = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.avatar,
        1.5,
      );
      final b = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.avatar,
        1.5,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(AccessibilitySettings.defaults));
    });

    test('touch targets never drop below 48 dp', () {
      const s = AccessibilitySettings.defaults;
      expect(s.touchTarget(20), AccessibilitySettings.minTouchTarget);
      expect(s.touchTarget(56), 56);
      expect(
        s.copyWith(ScaleCategory.touchTarget, 2.0).touchTarget(20),
        AccessibilitySettings.minTouchTarget,
      );
    });

    test('button boxes fit the scaled icon', () {
      final s = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.button,
        2.0,
      );
      expect(s.icon(), 48);
      expect(s.buttonBox(48), greaterThanOrEqualTo(s.icon() + 16));
    });

    test('defaults keep the original sizes', () {
      const s = AccessibilitySettings.defaults;
      expect(s.buttonBox(48), 48);
      expect(s.buttonBox(56), 56);
      expect(s.avatar(54), 54);
      expect(s.icon(), 24);
    });

    test('save and load round trip', () async {
      final store = await _store();
      final s = AccessibilitySettings.defaults
          .copyWith(ScaleCategory.text, 1.4)
          .copyWith(ScaleCategory.touchTarget, 1.7);
      await s.save(store);
      expect(AccessibilitySettings.load(store), s);
    });

    test(
      'load ignores values of the wrong type and clamps stored values',
      () async {
        final store = await _store({
          ScaleCategory.text.storageKey: 'big',
          ScaleCategory.avatar.storageKey: 7.0,
        });
        final s = AccessibilitySettings.load(store);
        expect(s.textScale, 1.0);
        expect(s.avatarScale, ScaleCategory.avatar.max);
      },
    );
  });

  group('fontSizeFactor migration', () {
    test('old chat font size becomes the text scale once', () async {
      final store = await _store({AppSettings.fontSizeFactor.key: 1.5});
      final controller = AccessibilityController(store);
      expect(controller.settings.textScale, 1.5);
      expect(store.getDouble(ScaleCategory.text.storageKey), 1.5);

      // A later change of the old key no longer has any effect.
      await store.setDouble(AppSettings.fontSizeFactor.key, 2.0);
      expect(AccessibilityController(store).settings.textScale, 1.5);
    });

    test('old values outside the range are clamped', () async {
      final store = await _store({AppSettings.fontSizeFactor.key: 0.5});
      expect(
        AccessibilityController(store).settings.textScale,
        ScaleCategory.text.min,
      );
    });

    test('our own stored value wins over the old one', () async {
      final store = await _store({
        AppSettings.fontSizeFactor.key: 2.0,
        ScaleCategory.text.storageKey: 1.2,
      });
      expect(AccessibilityController(store).settings.textScale, 1.2);
    });
  });

  group('AccessibilityController', () {
    test('apply persists and can be undone', () async {
      final store = await _store();
      final controller = AccessibilityController(store);
      expect(controller.canUndo, isFalse);

      await controller.apply(ScaleCategory.button, 1.5);
      expect(controller.settings.buttonScale, 1.5);
      expect(store.getDouble(ScaleCategory.button.storageKey), 1.5);
      expect(controller.canUndo, isTrue);

      await controller.undo();
      expect(controller.settings.buttonScale, 1.0);
      expect(store.getDouble(ScaleCategory.button.storageKey), 1.0);
      expect(controller.canUndo, isFalse);
    });

    test('undo only covers the last change', () async {
      final controller = AccessibilityController(await _store());
      await controller.apply(ScaleCategory.button, 1.5);
      await controller.apply(ScaleCategory.avatar, 1.8);
      await controller.undo();
      expect(controller.settings.avatarScale, 1.0);
      expect(controller.settings.buttonScale, 1.5);
      expect(controller.canUndo, isFalse);
    });

    test('a slider drag is one undo step and saves only at the end', () async {
      final store = await _store();
      final controller = AccessibilityController(store);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.beginEdit();
      controller.preview(ScaleCategory.text, 1.1);
      controller.preview(ScaleCategory.text, 1.3);
      controller.preview(ScaleCategory.text, 1.6);
      expect(controller.settings.textScale, 1.6);
      expect(store.getDouble(ScaleCategory.text.storageKey), 1.0);
      expect(notifications, 3);

      await controller.endEdit();
      expect(store.getDouble(ScaleCategory.text.storageKey), 1.6);

      await controller.undo();
      expect(controller.settings.textScale, 1.0);
    });

    test('a drag that ends where it started creates no undo step', () async {
      final controller = AccessibilityController(await _store());
      controller.beginEdit();
      controller.preview(ScaleCategory.text, 1.5);
      controller.preview(ScaleCategory.text, 1.0);
      await controller.endEdit();
      expect(controller.canUndo, isFalse);
    });

    test('reset restores defaults and is undoable', () async {
      final store = await _store();
      final controller = AccessibilityController(store);
      await controller.apply(ScaleCategory.avatar, 2.0);
      await controller.reset();
      expect(controller.settings, AccessibilitySettings.defaults);
      expect(store.getDouble(ScaleCategory.avatar.storageKey), 1.0);

      await controller.undo();
      expect(controller.settings.avatarScale, 2.0);
    });

    test('settings survive a restart', () async {
      final store = await _store();
      await AccessibilityController(store).apply(ScaleCategory.avatar, 1.4);
      expect(AccessibilityController(store).settings.avatarScale, 1.4);
    });
  });
}
