// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/model/settings_call_validator.dart';
import 'package:fluffychat/personalization/model/settings_functions.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsFunctions', () {
    test('one function per category, with unique names', () {
      expect(SettingsFunctions.all.length, ScaleCategory.values.length);
      expect(
        SettingsFunctions.all.map((f) => f.name).toSet().length,
        ScaleCategory.values.length,
      );
    });

    test('names map back to their category', () {
      for (final category in ScaleCategory.values) {
        final name = SettingsFunctions.nameFor(category);
        expect(SettingsFunctions.categoryFor(name), category, reason: name);
      }
      expect(SettingsFunctions.categoryFor('delete_all_messages'), isNull);
    });

    test('readable names', () {
      expect(
        SettingsFunctions.nameFor(ScaleCategory.button),
        'adjust_button_size',
      );
      expect(
        SettingsFunctions.nameFor(ScaleCategory.inputText),
        'adjust_input_text_size',
      );
    });

    test('descriptions state the allowed range of their category', () {
      for (final category in ScaleCategory.values) {
        final f = SettingsFunctions.all.firstWhere(
          (f) => f.name == SettingsFunctions.nameFor(category),
        );
        expect(f.description, contains('${category.min}'));
        expect(f.description, contains('${category.max}'));
      }
    });

    test('parameters are a JSON schema with a direction enum', () {
      final params = SettingsFunctions.all.first.parameters;
      expect(params['type'], 'object');
      final properties = params['properties'] as Map;
      expect((properties['direction'] as Map)['enum'], ['bigger', 'smaller']);
      expect(
        (properties['steps'] as Map)['maximum'],
        SettingsFunctions.maxSteps,
      );
      expect(params['required'], ['direction']);
    });
  });

  group('SettingsCallValidator', () {
    const defaults = AccessibilitySettings.defaults;

    ValidationResult validate(
      String name,
      Map<String, Object?> args, [
      AccessibilitySettings settings = defaults,
    ]) => SettingsCallValidator.validate(ProposedCall(name, args), settings);

    test('no call is rejected', () {
      final result = SettingsCallValidator.validate(null, defaults);
      expect((result as RejectedCall).reason, RejectionReason.noCall);
    });

    test('unknown functions are rejected', () {
      final result = validate('send_message', {'direction': 'bigger'});
      expect((result as RejectedCall).reason, RejectionReason.unknownFunction);
    });

    test('a valid call becomes one step bigger by default', () {
      final result =
          validate('adjust_button_size', {'direction': 'bigger'}) as ValidCall;
      expect(result.category, ScaleCategory.button);
      expect(result.from, 1.0);
      expect(result.to, 1.1);
    });

    test('direction is case and space insensitive', () {
      final result =
          validate('adjust_text_size', {'direction': ' Smaller '}) as ValidCall;
      expect(result.to, 0.9);
    });

    test('a missing or unknown direction is rejected', () {
      for (final args in [
        <String, Object?>{},
        {'direction': 'huge'},
        {'direction': 3},
      ]) {
        final result = validate('adjust_text_size', args);
        expect(
          (result as RejectedCall).reason,
          RejectionReason.invalidArguments,
          reason: '$args',
        );
      }
    });

    test('steps are clamped and accept numeric strings', () {
      expect(
        (validate('adjust_avatar_size', {'direction': 'bigger', 'steps': 10})
                as ValidCall)
            .to,
        1.3,
      );
      expect(
        (validate('adjust_avatar_size', {'direction': 'bigger', 'steps': 0})
                as ValidCall)
            .to,
        1.1,
      );
      expect(
        (validate('adjust_avatar_size', {'direction': 'bigger', 'steps': '2'})
                as ValidCall)
            .to,
        1.2,
      );
    });

    test('non-numeric steps are rejected', () {
      final result = validate('adjust_avatar_size', {
        'direction': 'bigger',
        'steps': 'many',
      });
      expect((result as RejectedCall).reason, RejectionReason.invalidArguments);
    });

    test('the result never leaves the allowed range', () {
      final settings = defaults.copyWith(ScaleCategory.text, 1.9);
      final result =
          validate('adjust_text_size', {
                'direction': 'bigger',
                'steps': 3,
              }, settings)
              as ValidCall;
      expect(result.to, ScaleCategory.text.max);
    });

    test('a change at the limit is rejected as such', () {
      final result = validate('adjust_button_size', {'direction': 'smaller'});
      expect((result as RejectedCall).reason, RejectionReason.alreadyAtLimit);
      expect(result.category, ScaleCategory.button);
    });
  });
}
