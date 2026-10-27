// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

import '../accessibility_settings.dart';
import '../personalization_l10n.dart';

/// Shows the affected element side by side at the current size and at the
/// proposed size, so the user sees what the change does before applying it.
class ChangePreview extends StatelessWidget {
  final ScaleCategory category;
  final double from;
  final double to;

  const ChangePreview({
    required this.category,
    required this.from,
    required this.to,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    Widget column(String label, double value, {bool highlight = false}) =>
        Expanded(
          child: Column(
            mainAxisSize: .min,
            children: [
              Text(
                '$label  × ${value.toStringAsFixed(1)}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: highlight ? FontWeight.bold : null,
                  color: highlight ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(height: 8),
              // Scale down instead of overflowing on narrow screens.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: _Sample(category: category, value: value),
              ),
            ],
          ),
        );

    return Container(
      key: const Key('change_preview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
      ),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          column(l10n.previewNow, from),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
          ),
          column(l10n.previewSuggested, to, highlight: true),
        ],
      ),
    );
  }
}

/// One sample element drawn at [value] times its normal size. Sizes are
/// computed here instead of read from the live settings, so both sides of the
/// preview can be shown at once.
class _Sample extends StatelessWidget {
  final ScaleCategory category;
  final double value;

  const _Sample({required this.category, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    switch (category) {
      case ScaleCategory.text:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.otherBubbleColor,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          ),
          child: Text(
            l10n.previewReply,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: AppConfig.messageFontSize * value,
              color: theme.colorScheme.onSurface,
            ),
          ),
        );
      case ScaleCategory.inputText:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
          child: Text(
            l10n.typeMessage,
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: AppConfig.messageFontSize * value),
          ),
        );
      case ScaleCategory.button:
        final icon = 24 * value;
        return SizedBox.square(
          dimension: max(48.0, icon + 16),
          child: Icon(Icons.send, size: icon, color: theme.colorScheme.primary),
        );
      case ScaleCategory.touchTarget:
        // The outlined box is the area that reacts to a tap.
        final area = max(AccessibilitySettings.minTouchTarget, 48 * value);
        return Container(
          width: area,
          height: area,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(32),
            border: Border.all(color: theme.colorScheme.primary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.send, color: theme.colorScheme.primary),
        );
      case ScaleCategory.avatar:
        final size = 36 * value;
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            l10n.previewChatName.characters.first,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: size / 2.5,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        );
    }
  }
}
