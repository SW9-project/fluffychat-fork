// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';

import '../accessibility_settings.dart';
import '../heuristics/heuristic.dart';
import 'settings_call_validator.dart';
import 'settings_functions.dart';
import 'settings_intent_model.dart';

/// What the Assist tab does with the model's answer to one prompt.
sealed class AssistResult {
  const AssistResult();
}

/// The model picked a heuristic and its change is within the allowed range.
class AssistProposal extends AssistResult {
  final Heuristic heuristic;
  final ScaleCategory category;
  final double from;
  final double to;

  const AssistProposal(this.heuristic, this.category, this.from, this.to);
}

/// The model picked a heuristic, but its setting cannot change further.
class AssistAtLimit extends AssistResult {
  final Heuristic heuristic;
  final ScaleCategory category;

  const AssistAtLimit(this.heuristic, this.category);
}

/// No call, an unknown function or unusable arguments. The app never invents
/// a change in this case.
class AssistNoSuggestion extends AssistResult {
  final RejectionReason reason;

  const AssistNoSuggestion(this.reason);
}

/// The heuristics are the model's knowledge: each heuristic with a `rule` is
/// offered as one function, and the model only picks which one fits the
/// user's prompt and how many steps. Which setting changes and in which
/// direction come from the heuristic's `change`, never from the model.
abstract final class HeuristicFunctions {
  static const stepsParam = 'steps';

  static String nameFor(Heuristic heuristic) =>
      'heuristic_${heuristic.id.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';

  static List<Heuristic> _offered(List<Heuristic> heuristics) => [
    for (final h in heuristics)
      if (h.rule?.trim().isNotEmpty ?? false) h,
  ];

  /// The only functions the model is offered.
  static List<FunctionDeclaration> declarationsFor(
    List<Heuristic> heuristics,
  ) => [
    for (final h in _offered(heuristics))
      FunctionDeclaration(
        name: nameFor(h),
        description: h.rule!.trim(),
        parameters: {
          'type': 'object',
          'properties': {
            stepsParam: {
              'type': 'integer',
              'minimum': 1,
              'maximum': SettingsFunctions.maxSteps,
              'description':
                  'How much to change: 1 is a little, '
                  '${SettingsFunctions.maxSteps} is a lot. Use 1 when unsure.',
            },
          },
          'required': <String>[],
        },
      ),
  ];

  static Heuristic? heuristicFor(String name, List<Heuristic> heuristics) =>
      _offered(heuristics).firstWhereOrNull((h) => nameFor(h) == name);

  /// Turns the model's [call] into a change and checks it against the
  /// allowed ranges with [SettingsCallValidator].
  static AssistResult interpret(
    ProposedCall? call,
    List<Heuristic> heuristics,
    AccessibilitySettings settings,
  ) {
    if (call == null) {
      return const AssistNoSuggestion(RejectionReason.noCall);
    }
    final heuristic = heuristicFor(call.name, heuristics);
    if (heuristic == null) {
      return const AssistNoSuggestion(RejectionReason.unknownFunction);
    }

    final raw = call.args[stepsParam];
    final scale = heuristic.steps.abs();
    final steps = switch (raw) {
      _ when scale == 1 => raw,
      null => scale,
      num() => raw * scale,
      String() => switch (num.tryParse(raw.trim())) {
        final n? => n * scale,
        null => raw,
      },
      _ => raw,
    };
    final result = SettingsCallValidator.validate(
      ProposedCall(SettingsFunctions.nameFor(heuristic.category), {
        SettingsFunctions.directionParam: heuristic.steps < 0
            ? SettingsFunctions.smaller
            : SettingsFunctions.bigger,
        SettingsFunctions.stepsParam: steps,
      }),
      settings,
    );
    return switch (result) {
      ValidCall(:final category, :final from, :final to) => AssistProposal(
        heuristic,
        category,
        from,
        to,
      ),
      RejectedCall(reason: RejectionReason.alreadyAtLimit) => AssistAtLimit(
        heuristic,
        heuristic.category,
      ),
      RejectedCall(:final reason) => AssistNoSuggestion(reason),
    };
  }
}
