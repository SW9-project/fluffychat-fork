// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../accessibility_settings.dart';
import 'settings_functions.dart';
import 'settings_intent_model.dart';

enum RejectionReason {
  /// The model answered without calling a function.
  noCall,

  /// The function is not in the allowlist.
  unknownFunction,

  /// The arguments are missing or have the wrong type or value.
  invalidArguments,

  /// The setting is already at its minimum or maximum.
  alreadyAtLimit,
}

sealed class ValidationResult {
  const ValidationResult();
}

class ValidCall extends ValidationResult {
  final ScaleCategory category;
  final double from;
  final double to;

  const ValidCall(this.category, this.from, this.to);
}

class RejectedCall extends ValidationResult {
  final RejectionReason reason;
  final ScaleCategory? category;

  const RejectedCall(this.reason, [this.category]);
}

/// Checks a model's proposed call against the allowlist from
/// [SettingsFunctions] before anything is shown to the user. Unknown functions
/// and malformed arguments are rejected; step counts are clamped; the result
/// is clamped to the category's range.
abstract final class SettingsCallValidator {
  static ValidationResult validate(
    ProposedCall? call,
    AccessibilitySettings settings,
  ) {
    if (call == null) return const RejectedCall(RejectionReason.noCall);

    final category = SettingsFunctions.categoryFor(call.name);
    if (category == null) {
      return const RejectedCall(RejectionReason.unknownFunction);
    }

    final direction = call.args[SettingsFunctions.directionParam];
    final int sign;
    switch (direction is String ? direction.trim().toLowerCase() : null) {
      case SettingsFunctions.bigger:
        sign = 1;
      case SettingsFunctions.smaller:
        sign = -1;
      default:
        return RejectedCall(RejectionReason.invalidArguments, category);
    }

    final steps = _steps(call.args[SettingsFunctions.stepsParam]);
    if (steps == null) {
      return RejectedCall(RejectionReason.invalidArguments, category);
    }

    final from = settings[category];
    final to = category.normalize(from + sign * steps * category.step);
    if (to == from) {
      return RejectedCall(RejectionReason.alreadyAtLimit, category);
    }
    return ValidCall(category, from, to);
  }

  /// Steps default to 1, accept numbers and numeric strings, and are clamped
  /// to 1..maxSteps. Anything else is invalid.
  static int? _steps(Object? value) {
    if (value == null) return 1;
    final number = switch (value) {
      num() => value,
      String() => num.tryParse(value.trim()),
      _ => null,
    };
    if (number == null || number.isNaN) return null;
    return number.round().clamp(1, SettingsFunctions.maxSteps);
  }
}
