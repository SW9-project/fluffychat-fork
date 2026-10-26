// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:material_ui/material_ui.dart';

import 'accessibility_scope.dart';
import 'accessibility_settings.dart';
import 'model/ask_the_app_section.dart';
import 'personalization_l10n.dart';
import 'personalization_layer.dart';

/// Lets the user resize UI elements by hand, with a live preview.
class AccessibilitySettingsPage extends StatelessWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final settings = AccessibilityScope.of(context);
    final controller = AccessibilityScope.controllerOf(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: Text(l10n.accessibility),
      ),
      backgroundColor: theme.colorScheme.surface,
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.accessibilityDescription,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            if (PersonalizationLayer.maybeOf(context) case final layer?)
              AskTheAppSection(
                model: layer.model,
                manager: layer.manager,
                accessibility: controller,
              ),
            ListTile(
              title: Text(
                l10n.preview,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const _Preview(),
            const Divider(),
            for (final category in ScaleCategory.values) ...[
              ListTile(
                title: Text(l10n.categoryTitles[category]!),
                subtitle: Text(l10n.categoryDescriptions[category]!),
                trailing: Text(
                  '× ${settings[category].toStringAsFixed(1)}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Slider.adaptive(
                key: Key('accessibility_slider_${category.id}'),
                min: category.min,
                max: category.max,
                divisions: category.divisions,
                value: settings[category],
                label: '× ${settings[category].toStringAsFixed(1)}',
                semanticFormatterCallback: (value) =>
                    '× ${value.toStringAsFixed(1)}',
                onChangeStart: (_) => controller.beginEdit(),
                onChanged: (value) => controller.preview(category, value),
                onChangeEnd: (_) => controller.endEdit(),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    key: const Key('accessibility_undo'),
                    onPressed: controller.canUndo ? controller.undo : null,
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.undo),
                  ),
                  ElevatedButton.icon(
                    key: const Key('accessibility_reset'),
                    onPressed: settings == AccessibilitySettings.defaults
                        ? null
                        : controller.reset,
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l10n.reset),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small chat mock-up that uses the same sizes as the real chat.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final settings = AccessibilityScope.of(context);
    final avatarSize = settings.avatar(36);
    final buttonBox = settings.buttonBox(48);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            crossAxisAlignment: .end,
            children: [
              Avatar(name: l10n.previewChatName, size: avatarSize),
              const SizedBox(width: 8),
              Flexible(
                child: _PreviewBubble(
                  text: l10n.previewMessage,
                  color: theme.otherBubbleColor,
                  textColor: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _PreviewBubble(
              text: l10n.previewReply,
              color: theme.bubbleColor,
              textColor: theme.onBubbleColor,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            child: AccessibilityIconButtons(
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: buttonBox,
                    child: IconButton(
                      onPressed: () {},
                      color: theme.colorScheme.onSurfaceVariant,
                      icon: const Icon(Icons.emoji_emotions_outlined),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      l10n.typeMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: AccessibilityTextScale.inputTextScaler(
                        context,
                      ),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: buttonBox,
                    child: IconButton(
                      onPressed: () {},
                      color: theme.colorScheme.onSurfaceVariant,
                      icon: const Icon(Icons.attach_file),
                    ),
                  ),
                  SizedBox.square(
                    dimension: buttonBox,
                    child: IconButton(
                      onPressed: () {},
                      color: theme.colorScheme.primary,
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _PreviewBubble({
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
    ),
    child: Text(
      text,
      style: TextStyle(color: textColor, fontSize: AppConfig.messageFontSize),
    ),
  );
}
