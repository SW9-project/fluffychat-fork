// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_scope.dart';

/// Dialog routes sit above the app's accessibility wrappers.
Future<T?> showSimpleViewDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final textScaler = MediaQuery.textScalerOf(context);
  final sizes = AccessibilityScope.of(context);
  final theme = Theme.of(context);
  final buttonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(sizes.touchTarget(48), sizes.buttonBox(48)),
    ),
  );
  final accessibility = AccessibilityScope.maybeControllerOf(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final child = MediaQuery(
        data: MediaQuery.of(dialogContext).copyWith(textScaler: textScaler),
        child: Theme(
          data: theme.copyWith(
            filledButtonTheme: FilledButtonThemeData(
              style:
                  theme.filledButtonTheme.style?.merge(buttonStyle) ??
                  buttonStyle,
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style:
                  theme.outlinedButtonTheme.style?.merge(buttonStyle) ??
                  buttonStyle,
            ),
            textButtonTheme: TextButtonThemeData(
              style:
                  theme.textButtonTheme.style?.merge(buttonStyle) ??
                  buttonStyle,
            ),
          ),
          child: Builder(builder: builder),
        ),
      );
      return accessibility == null
          ? child
          : AccessibilityScope(controller: accessibility, child: child);
    },
  );
}
