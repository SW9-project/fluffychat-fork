// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'settings_functions.dart';
import 'settings_intent_model.dart';

/// Optional contract for future models trained for simplified interfaces.
/// The current pilot has only text/button heuristics; explicit UI actions
/// use the same preview without pretending a model interpreted a request.
abstract final class SimpleViewFunction {
  static const declaration = FunctionDeclaration(
    name: 'change_interface',
    description:
        'Choose a simpler interface with fewer visible secondary options, or return to the full interface. Does not change text or button sizes.',
    parameters: {
      'type': 'object',
      'properties': {
        'view': {
          'type': 'string',
          'enum': ['simple', 'full'],
        },
      },
      'required': ['view'],
      'additionalProperties': false,
    },
  );
  static bool? validate(ProposedCall? call) {
    if (call?.name != declaration.name || call!.args.length != 1) return null;
    return switch (call.args['view']) {
      'simple' => true,
      'full' => false,
      _ => null,
    };
  }
}
