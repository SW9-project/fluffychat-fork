// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';

import '../accessibility_settings.dart';
import '../heuristics/heuristic.dart';
import '../suggestions/suggestion.dart';
import 'heuristic_functions.dart';
import 'settings_call_validator.dart';
import 'settings_functions.dart';
import 'settings_intent_model.dart';

/// V2's tool names, restricted to the settings this app can apply.
/// Only validated model output is translated; prompts are never classified
/// with local keywords and unknown actions are never guessed.
abstract final class V2SettingsFunctions {
  static const names = {
    'change_text_zoom': ScaleCategory.text,
    'change_button': ScaleCategory.button,
  };

  static Heuristic? _enabled(
    ScaleCategory category,
    List<Heuristic> heuristics,
  ) => heuristics.firstWhereOrNull(
    (h) => h.category == category && (h.rule?.trim().isNotEmpty ?? false),
  );

  static List<FunctionDeclaration> declarationsFor(
    List<Heuristic> heuristics,
  ) => [
    for (final entry in names.entries)
      if (_enabled(entry.value, heuristics) != null)
        FunctionDeclaration(
          name: entry.key,
          description: entry.value == ScaleCategory.text
              ? 'Change the size of text. Use bigger when text is too small to read, smaller when text is too large.'
              : 'Change the size of buttons and icons. Use bigger when buttons are too small or hard to tap, smaller when they are too large.',
          parameters: const {
            'type': 'object',
            'properties': {
              'direction': {
                'type': 'string',
                'enum': ['bigger', 'smaller'],
              },
            },
            'required': ['direction'],
            'additionalProperties': false,
          },
        ),
  ];

  static AssistResult interpret(
    ProposedCall? call,
    List<Heuristic> heuristics,
    AccessibilitySettings settings,
  ) {
    final category = names[call?.name];
    if (category == null) {
      return AssistNoSuggestion(
        call == null ? RejectionReason.noCall : RejectionReason.unknownFunction,
      );
    }
    final original = _enabled(category, heuristics);
    if (original == null) {
      return const AssistNoSuggestion(RejectionReason.unknownFunction);
    }
    final direction = call!.args['direction'];
    if (call.args.length != 1 ||
        (direction != 'bigger' && direction != 'smaller')) {
      return const AssistNoSuggestion(RejectionReason.invalidArguments);
    }
    final bigger = direction == 'bigger';
    final text = category == ScaleCategory.text;
    final proposal = Heuristic(
      id: Suggestion.modelRequestId,
      source: 'SW9 v2 user request',
      condition: original.condition,
      category: category,
      steps: bigger ? 1 : -1,
      cooldown: Duration.zero,
      descriptions: {
        'en': text
            ? (bigger ? 'Make the text bigger?' : 'Make the text smaller?')
            : (bigger
                  ? 'Make the buttons bigger?'
                  : 'Make the buttons smaller?'),
        'es': text
            ? (bigger
                  ? '¿Aumentar el tamaño del texto?'
                  : '¿Reducir el tamaño del texto?')
            : (bigger
                  ? '¿Aumentar el tamaño de los botones?'
                  : '¿Reducir el tamaño de los botones?'),
        'da': text
            ? (bigger ? 'Gør teksten større?' : 'Gør teksten mindre?')
            : (bigger ? 'Gør knapperne større?' : 'Gør knapperne mindre?'),
      },
    );
    final validated = SettingsCallValidator.validate(
      ProposedCall(SettingsFunctions.nameFor(category), {
        'direction': direction,
        'steps': 1,
      }),
      settings,
    );
    return switch (validated) {
      ValidCall(:final from, :final to) => AssistProposal(
        proposal,
        category,
        from,
        to,
      ),
      RejectedCall(reason: RejectionReason.alreadyAtLimit) => AssistAtLimit(
        proposal,
        category,
      ),
      RejectedCall(:final reason) => AssistNoSuggestion(reason),
    };
  }
}
