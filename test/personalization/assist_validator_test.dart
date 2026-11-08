// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/assist/assist_prompt.dart';
import 'package:fluffychat/personalization/assist/assist_result.dart';
import 'package:fluffychat/personalization/assist/assist_tools.dart';
import 'package:fluffychat/personalization/assist/assist_validator.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/settings_call_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final template = AssistPromptTemplate.parse(
    File(AssistPromptTemplate.assetPath).readAsStringSync(),
  );
  final tools = AssistTools.build(template);
  final heuristics = HeuristicsConfig.fromJson(
    jsonDecode(
      File('assets/personalization_heuristics.json').readAsStringSync(),
    ),
  ).heuristics;

  AssistResult check(
    List<AssistToolCall> calls, {
    AccessibilitySettings settings = AccessibilitySettings.defaults,
  }) => AssistValidator.validate(
    calls,
    tools: tools,
    template: template,
    heuristics: heuristics,
    settings: settings,
  );

  AssistToolCall call(String name, Object? args) =>
      AssistToolCall(name, args is Map ? jsonEncode(args) : args);

  Map<String, Object?> args(
    Object? value, {
    Object? heuristic = 'near-miss-buttons',
    Object? rationale = 'Bigger buttons are easier to hit.',
  }) => {'value': value, 'heuristic': heuristic, 'rationale': rationale};

  group('AssistValidator', () {
    test('accepts a valid call', () {
      final result = check([call('set_button_scale', args(1.3))]);
      expect(result, isA<AssistProposal>());
      result as AssistProposal;
      expect(result.category, ScaleCategory.button);
      expect(result.from, 1.0);
      expect(result.to, 1.3);
      expect(result.clamped, isFalse);
      expect(result.rationale, 'Bigger buttons are easier to hit.');
      // The id matches the premade heuristic, so its descriptions are kept.
      expect(result.heuristic.id, 'near-miss-buttons');
      expect(result.heuristic.description('da'), contains('knapper'));
    });

    test('accepts already decoded arguments and numeric strings', () {
      final result = check([
        AssistToolCall('set_text_scale', {
          'value': '1.2',
          'heuristic': 'text-zoom',
          'rationale': 'Bigger text is easier to read.',
        }),
      ]);
      expect((result as AssistProposal).to, 1.2);
    });

    test('rejects no call', () {
      expect(
        check([]),
        isA<AssistNoSuggestion>().having(
          (r) => r.reason,
          'reason',
          RejectionReason.noCall,
        ),
      );
    });

    test('rejects an unknown tool or setting', () {
      for (final name in ['set_screen_reader', 'adjust_text_size', '']) {
        expect(
          check([call(name, args(1.3))]),
          isA<AssistNoSuggestion>().having(
            (r) => r.reason,
            'reason',
            RejectionReason.unknownFunction,
          ),
          reason: name,
        );
      }
    });

    test('rejects a heuristic not offered for the tool', () {
      for (final heuristic in ['made-up', 'small-avatars', null, 3]) {
        expect(
          check([call('set_button_scale', args(1.3, heuristic: heuristic))]),
          isA<AssistNoSuggestion>().having(
            (r) => r.reason,
            'reason',
            RejectionReason.unknownHeuristic,
          ),
          reason: '$heuristic',
        );
      }
    });

    test('rejects unusable values and arguments', () {
      for (final bad in <Object?>[
        call('set_button_scale', args('big')),
        call('set_button_scale', args(null)),
        call('set_button_scale', args(double.nan.toString())),
        call('set_button_scale', args(true)),
        call('set_button_scale', '{not json'),
        call('set_button_scale', '[1.3]'),
      ]) {
        expect(
          check([bad as AssistToolCall]),
          isA<AssistNoSuggestion>().having(
            (r) => r.reason,
            'reason',
            RejectionReason.invalidArguments,
          ),
        );
      }
    });

    test('clamps out-of-range values and snaps to the step', () {
      final high = check([call('set_button_scale', args(5))]) as AssistProposal;
      expect(high.to, 2.0);
      expect(high.clamped, isTrue);

      final low =
          check([
                call('set_text_scale', args(0.1, heuristic: 'too-big-crowded')),
              ])
              as AssistProposal;
      expect(low.to, 0.8);
      expect(low.clamped, isTrue);
      expect(low.heuristic.steps, -1);

      final snapped =
          check([call('set_button_scale', args(1.234))]) as AssistProposal;
      expect(snapped.to, 1.2);
      expect(snapped.clamped, isFalse);
    });

    test('reports a setting already at its limit', () {
      final atMax = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.button,
        2.0,
      );
      expect(
        check([call('set_button_scale', args(2.4))], settings: atMax),
        isA<AssistAtLimit>(),
      );
    });

    test('reports no change when the value is the current one', () {
      final settings = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.button,
        1.4,
      );
      expect(
        check([call('set_button_scale', args(1.4))], settings: settings),
        isA<AssistNoSuggestion>().having(
          (r) => r.reason,
          'reason',
          RejectionReason.noChange,
        ),
      );
    });

    test('uses only the first acceptable call', () {
      final result =
          check([
                call('set_unknown', args(1.3)),
                call('set_button_scale', args(1.3)),
                call('set_text_scale', args(1.5, heuristic: 'text-zoom')),
              ])
              as AssistProposal;
      expect(result.category, ScaleCategory.button);
    });

    test('prefers the most helpful rejection', () {
      final atMax = AccessibilitySettings.defaults.copyWith(
        ScaleCategory.button,
        2.0,
      );
      expect(
        check([
          call('set_unknown', args(1.3)),
          call('set_button_scale', args(2.0)),
        ], settings: atMax),
        isA<AssistAtLimit>(),
      );
    });

    test('builds a heuristic from heuristics.md for an id without one', () {
      final result =
          check([
                call('set_avatar_scale', args(1.2, heuristic: 'small-avatars')),
              ])
              as AssistProposal;
      expect(result.heuristic.id, 'small-avatars');
      expect(result.heuristic.source, AssistPromptTemplate.assetPath);
      expect(result.heuristic.category, ScaleCategory.avatar);
    });

    test('a missing rationale falls back to the premade text', () {
      final result =
          check([call('set_button_scale', args(1.3, rationale: null))])
              as AssistProposal;
      expect(result.rationale, isNull);
    });
  });

  group('cleanRationale', () {
    test('strips markup and control characters', () {
      expect(
        AssistValidator.cleanRationale('**Bigger** buttons\n\nare `easier`.'),
        'Bigger buttons are easier.',
      );
      expect(AssistValidator.cleanRationale('   '), isNull);
      expect(AssistValidator.cleanRationale(42), isNull);
    });

    test('shortens long text at a word', () {
      final long = List.filled(80, 'word').join(' ');
      final cleaned = AssistValidator.cleanRationale(long)!;
      expect(cleaned.length, lessThanOrEqualTo(AssistTool.rationaleMaxLength));
      expect(cleaned, endsWith('word…'));
    });
  });
}
