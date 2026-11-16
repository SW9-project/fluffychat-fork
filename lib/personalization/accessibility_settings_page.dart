// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:material_ui/material_ui.dart';

import 'accessibility_scope.dart';
import 'accessibility_settings.dart';
import 'appearance_l10n.dart';
import 'personalization_l10n.dart';
import 'study/study_screen.dart';

/// Lets the user resize UI elements by hand, with a live preview.
class AccessibilitySettingsPage extends StatelessWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final settings = AccessibilityScope.of(context);
    final controller = AccessibilityScope.controllerOf(context);
    final words = AppearanceL10n.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: StudyEntry(child: Text(l10n.accessibility)),
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
            for (final category in ScaleCategory.inGroup(ScaleGroup.general))
              _ScaleSlider(category: category),
            _Group(
              title: words.textGroup,
              children: [
                for (final category in ScaleCategory.inGroup(ScaleGroup.text))
                  _ScaleSlider(category: category),
              ],
            ),
            _Group(
              title: words.buttonsGroup,
              children: [
                for (final category in ScaleCategory.inGroup(
                  ScaleGroup.buttons,
                ))
                  _ScaleSlider(category: category),
              ],
            ),
            const _ChatTextSection(),
            const Divider(),
            for (final toggle in AccessibilityToggle.values)
              SwitchListTile.adaptive(
                key: Key('accessibility_toggle_${toggle.id}'),
                title: Text(words.toggleTitles[toggle]!),
                subtitle: Text(words.toggleDescriptions[toggle]!),
                value: settings.isOn(toggle),
                onChanged: (on) => controller.setToggle(toggle, on),
              ),
            const _ThemeSection(),
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

/// One size with its slider. A drag is one undoable change.
///
/// A size on top of another, such as the titles on top of the text size,
/// shows its whole size, so it moves with the size below it, within its own
/// range. Dragging it changes only this size, and a button puts it back on the
/// size below.
class _ScaleSlider extends StatelessWidget {
  final ScaleCategory category;

  const _ScaleSlider({required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final words = AppearanceL10n.of(context);
    final settings = AccessibilityScope.of(context);
    final controller = AccessibilityScope.controllerOf(context);
    final digits = category.step < 0.1 ? 2 : 1;
    String label(double value) => '× ${value.toStringAsFixed(digits)}';
    final parent = category.parent;
    final value = settings.effective(category);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        ListTile(
          title: Text(l10n.categoryTitles[category]!),
          subtitle: Text(l10n.categoryDescriptions[category]!),
          trailing: Row(
            mainAxisSize: .min,
            children: [
              Text(label(value), style: theme.textTheme.titleMedium),
              if (parent != null && settings[category] != 1.0)
                IconButton(
                  key: Key('accessibility_match_${category.id}'),
                  tooltip: words.matchParent(l10n.categoryTitles[parent]!),
                  icon: const Icon(Icons.link),
                  onPressed: () => controller.apply(category, 1.0),
                ),
            ],
          ),
        ),
        Slider.adaptive(
          key: Key('accessibility_slider_${category.id}'),
          min: category.min,
          max: category.max,
          divisions: category.divisions,
          value: value,
          label: label(value),
          semanticFormatterCallback: label,
          onChangeStart: (_) => controller.beginEdit(),
          onChanged: (value) => controller.preview(category, value),
          onChangeEnd: (_) => controller.endEdit(),
        ),
      ],
    );
  }
}

/// Settings most people never need, folded away until opened.
class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(title),
    childrenPadding: EdgeInsets.zero,
    children: children,
  );
}

/// Chats with their own text size, which the assistant sets. Each can be
/// changed here or put back to normal.
class _ChatTextSection extends StatelessWidget {
  const _ChatTextSection();

  @override
  Widget build(BuildContext context) {
    final words = AppearanceL10n.of(context);
    final settings = AccessibilityScope.of(context);
    final controller = AccessibilityScope.controllerOf(context);
    final client = Matrix.of(context).client;
    final chats = settings.chatTextScales;
    const range = AccessibilitySettings.chatTextRange;
    // A chat's slider shows the whole message size, on top of the text in
    // messages.
    final below = settings.effective(ScaleCategory.messageText);
    return _Group(
      title: words.chatTextTitle,
      children: [
        ListTile(subtitle: Text(words.chatTextDescription)),
        for (final roomId in chats.keys) ...[
          ListTile(
            title: Text(
              client.getRoomById(roomId)?.getLocalizedDisplayname() ?? roomId,
            ),
            trailing: TextButton(
              onPressed: () =>
                  controller.applySettings(settings.withChatText(roomId, 1.0)),
              child: Text(words.chatTextNormal),
            ),
          ),
          Slider.adaptive(
            min: range.min,
            max: range.max,
            divisions: range.divisions,
            value: settings.messageScale(roomId),
            label: '× ${settings.messageScale(roomId).toStringAsFixed(1)}',
            semanticFormatterCallback: (v) => '× ${v.toStringAsFixed(1)}',
            onChangeStart: (_) => controller.beginEdit(),
            onChanged: (value) =>
                controller.previewChatText(roomId, value / below),
            onChangeEnd: (_) => controller.endEdit(),
          ),
        ],
      ],
    );
  }
}

/// FluffyChat's own light or dark setting, here too because the assistant
/// can change it.
class _ThemeSection extends StatefulWidget {
  const _ThemeSection();

  @override
  State<_ThemeSection> createState() => _ThemeSectionState();
}

class _ThemeSectionState extends State<_ThemeSection> {
  @override
  Widget build(BuildContext context) {
    final words = AppearanceL10n.of(context);
    final controller = ThemeController.of(context);
    // Rebuilds when the theme changes, also from the assistant.
    Theme.of(context);
    return ListTile(
      title: Text(words.themeTitle),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SegmentedButton<ThemeMode>(
          key: const Key('accessibility_theme'),
          segments: [
            for (final mode in const [
              ThemeMode.system,
              ThemeMode.light,
              ThemeMode.dark,
            ])
              ButtonSegment(value: mode, label: Text(words.themeModes[mode]!)),
          ],
          selected: {controller.themeMode},
          onSelectionChanged: (modes) async {
            await controller.setThemeMode(modes.single);
            if (mounted) setState(() {});
          },
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
      style: TextStyle(
        color: textColor,
        fontSize: AppConfig.messageFontSize,
        height: AccessibilityScope.of(context).lineHeight,
      ),
    ),
  );
}
