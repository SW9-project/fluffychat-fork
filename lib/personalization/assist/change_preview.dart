// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

import '../accessibility_scope.dart';
import '../accessibility_settings.dart';
import '../appearance_l10n.dart';
import '../personalization_l10n.dart';
import '../suggestions/suggestion.dart';

/// Shows the affected part of a chat at the current settings and at the
/// proposed ones, one above the other, so the user sees what the change does
/// before applying it.
class ChangePreview extends StatelessWidget {
  final SettingsChange change;

  const ChangePreview({required this.change, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final parts = _Part.of(change);
    final room = change.changedChat;
    final sizes = _sizes(l10n, change);
    // Each side gets the full width and text wraps instead of shrinking:
    // side by side on a phone, both samples would be shrunk to the same
    // width and look the same size.
    Widget side(
      String label,
      AccessibilitySettings settings,
      ThemeMode? mode, {
      bool highlight = false,
    }) => Column(
      crossAxisAlignment: .start,
      children: [
        Text(
          [label, ...sizes(settings)].join(' · '),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: highlight ? FontWeight.bold : null,
            color: highlight ? theme.colorScheme.primary : null,
          ),
        ),
        const SizedBox(height: 8),
        _Scene(settings: settings, themeMode: mode, parts: parts, room: room),
      ],
    );

    return Container(
      key: const Key('change_preview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          side(l10n.previewNow, change.from, change.themeFrom),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Icon(Icons.arrow_downward, color: theme.colorScheme.primary),
          ),
          side(
            l10n.previewSuggested,
            change.to,
            change.themeTo ?? change.themeFrom,
            highlight: true,
          ),
        ],
      ),
    );
  }
}

/// One entry per size the change touches, with its value in [settings], so
/// both sides show the actual and the new size.
List<String> Function(AccessibilitySettings settings) _sizes(
  PersonalizationL10n l10n,
  SettingsChange change,
) {
  final categories = [
    for (final c in ScaleCategory.values)
      if (change.from[c] != change.to[c]) c,
  ];
  final room = change.changedChat;
  String size(String title, double value, int digits) =>
      '$title: × ${value.toStringAsFixed(digits)}';
  return (settings) => [
    for (final c in categories)
      size(
        l10n.categoryTitles[c]!,
        settings.effective(c),
        c.step < 0.1 ? 2 : 1,
      ),
    if (room != null)
      size(
        l10n.categoryTitles[ScaleCategory.messageText]!,
        settings.messageScale(room),
        2,
      ),
  ];
}

/// The parts of a chat a preview shows.
enum _Part {
  message,
  chatList,
  title,
  input,
  inputButtons,
  topButtons,
  navigation,
  avatar;

  static Set<_Part> of(SettingsChange change) {
    final parts = <_Part>{};
    for (final c in ScaleCategory.values) {
      if (change.from[c] == change.to[c]) continue;
      parts.addAll(switch (c) {
        ScaleCategory.text => [message, chatList, title],
        ScaleCategory.messageText => [message],
        ScaleCategory.chatListText => [chatList],
        ScaleCategory.titleText => [title],
        ScaleCategory.inputText => [input],
        ScaleCategory.button ||
        ScaleCategory.touchTarget ||
        ScaleCategory.spacing => [inputButtons, topButtons],
        ScaleCategory.sendButton ||
        ScaleCategory.attachButton ||
        ScaleCategory.emojiButton ||
        ScaleCategory.microphoneButton => [inputButtons],
        ScaleCategory.backButton ||
        ScaleCategory.searchButton ||
        ScaleCategory.menuButton => [topButtons],
        ScaleCategory.navigationButton => [navigation],
        ScaleCategory.avatar => [avatar, message],
      });
    }
    if (change.from.buttonLabels != change.to.buttonLabels) {
      parts.addAll([inputButtons, topButtons]);
    }
    if (change.from.highContrast != change.to.highContrast) {
      parts.addAll([message, inputButtons]);
    }
    if (change.changedChat != null) parts.add(message);
    // A theme change or a reset with nothing else: the whole little chat.
    if (parts.isEmpty) {
      parts.addAll([title, message, inputButtons]);
    }
    return parts;
  }
}

/// A small chat drawn with [settings] instead of the live ones. Sizes are
/// computed here, so both sides of the preview can be shown at once.
class _Scene extends StatelessWidget {
  final AccessibilitySettings settings;
  final ThemeMode? themeMode;
  final Set<_Part> parts;

  /// The chat whose own text scale changes, if one does.
  final String? room;

  const _Scene({
    required this.settings,
    required this.themeMode,
    required this.parts,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system || null => MediaQuery.platformBrightnessOf(context),
    };
    final themed =
        Theme.of(context).brightness == brightness &&
        AccessibilityScope.of(context).highContrast == settings.highContrast;
    final child = Builder(builder: _content);
    // The scene only gets its own theme when it looks different from the
    // app around it.
    final scene = themed
        ? child
        : AccessibilityScope.withSettings(
            settings: settings,
            child: Builder(
              builder: (context) => Theme(
                data: FluffyThemes.buildTheme(
                  context,
                  brightness,
                  Theme.of(context).colorScheme.primary,
                ),
                child: child,
              ),
            ),
          );
    // The text scale of the app around the preview is replaced by the one
    // drawn here.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: AccessibilityTextScale.multiply(
          MediaQuery.textScalerOf(context),
          1 / AccessibilityScope.of(context).textScale,
        ),
        boldText: settings.highContrast,
      ),
      child: scene,
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final labels = AppearanceL10n.of(context);
    final s = settings;
    final text = s.textScale;
    // The system font size, without the app's own text scale (see build).
    final base = MediaQuery.textScalerOf(context);
    TextScaler scaled(double factor) =>
        AccessibilityTextScale.multiply(base, factor);
    final gap = s.spacing(8);
    final muted = s.highContrast
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    Widget button(
      IconData icon,
      String label,
      AccessibleButton kind, {
      Color? color,
    }) {
      final iconSize = s.icon(24, kind);
      final box = max(s.touchTarget(40), iconSize + 16);
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: gap / 2),
        child: Column(
          mainAxisSize: .min,
          children: [
            Container(
              width: box,
              height: box,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // The outline shows the area that reacts to a tap.
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(box / 2),
              ),
              child: Icon(icon, size: iconSize, color: color ?? muted),
            ),
            if (s.buttonLabels)
              Text(
                label,
                textScaler: scaled(text),
                style: TextStyle(fontSize: 11, color: muted),
              ),
          ],
        ),
      );
    }

    Widget buttons(List<Widget> children) =>
        Wrap(runSpacing: gap, crossAxisAlignment: .center, children: children);

    final rows = <Widget>[
      if (parts.contains(_Part.title))
        Text(
          l10n.previewChatName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textScaler: scaled(text * s.titleTextScale),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      if (parts.contains(_Part.topButtons))
        buttons([
          button(Icons.arrow_back, labels.labelBack, AccessibleButton.back),
          button(
            Icons.search_outlined,
            labels.labelSearch,
            AccessibleButton.search,
          ),
          button(Icons.more_vert, labels.labelMenu, AccessibleButton.menu),
        ]),
      if (parts.contains(_Part.chatList))
        Row(
          children: [
            _avatar(context, s.avatar(40)),
            SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    l10n.previewChatName,
                    textScaler: scaled(text * s.chatListTextScale),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    l10n.previewMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: scaled(text * s.chatListTextScale),
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      if (parts.contains(_Part.message) || parts.contains(_Part.avatar))
        Row(
          crossAxisAlignment: .end,
          children: [
            _avatar(context, s.avatar(36)),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.otherBubbleColor,
                  border: s.highContrast
                      ? Border.all(color: theme.colorScheme.onSurface)
                      : null,
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                ),
                child: Text(
                  l10n.previewMessage,
                  textScaler: scaled(s.messageScale(room)),
                  style: TextStyle(
                    fontSize: AppConfig.messageFontSize,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      if (parts.contains(_Part.input))
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          ),
          child: Text(
            l10n.typeMessage,
            textScaler: scaled(text * s.inputTextScale),
            style: TextStyle(color: muted),
          ),
        ),
      if (parts.contains(_Part.inputButtons))
        buttons([
          button(
            Icons.emoji_emotions_outlined,
            labels.labelEmoji,
            AccessibleButton.emoji,
          ),
          button(
            Icons.attach_file,
            labels.labelAttach,
            AccessibleButton.attach,
          ),
          button(
            Icons.mic_none_outlined,
            labels.labelMicrophone,
            AccessibleButton.microphone,
          ),
          button(
            Icons.send,
            labels.labelSend,
            AccessibleButton.send,
            color: theme.colorScheme.primary,
          ),
        ]),
      if (parts.contains(_Part.navigation))
        Row(
          mainAxisAlignment: .spaceEvenly,
          children: [
            for (final icon in const [
              Icons.chat_bubble_outline,
              Icons.chat_outlined,
              Icons.settings_outlined,
            ])
              Icon(
                icon,
                size: s.icon(24, AccessibleButton.navigation) / s.buttonScale,
                color: muted,
              ),
          ],
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
      ),
      child: Column(crossAxisAlignment: .stretch, spacing: gap, children: rows),
    );
  }

  Widget _avatar(BuildContext context, double size) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
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
