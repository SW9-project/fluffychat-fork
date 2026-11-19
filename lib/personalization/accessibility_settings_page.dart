// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/text_to_speech.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/glass_slider.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/liquid_glass.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/native_button.dart';
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
            const AccessibilityPreview(),
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
              if (toggle != AccessibilityToggle.tripleTapToRead ||
                  TextToSpeech.isSupported)
                SwitchListTile.adaptive(
                  key: Key('accessibility_toggle_${toggle.id}'),
                  title: Text(words.toggleTitles[toggle]!),
                  subtitle: Text(words.toggleDescriptions[toggle]!),
                  value: settings.isOn(toggle),
                  onChanged: (on) => controller.setToggle(toggle, on),
                ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  NativeButton(
                    key: const Key('accessibility_undo'),
                    onPressed: controller.canUndo ? controller.undo : null,
                    style: NativeButtonStyle.outlined,
                    icon: Icons.undo,
                    symbol: 'arrow.uturn.backward',
                    label: l10n.undo,
                  ),
                  NativeButton(
                    key: const Key('accessibility_reset'),
                    onPressed: settings == AccessibilitySettings.defaults
                        ? null
                        : controller.reset,
                    style: NativeButtonStyle.elevated,
                    icon: Icons.restart_alt,
                    symbol: 'arrow.counterclockwise',
                    label: l10n.reset,
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
        GlassSlider(
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
            trailing: NativeButton(
              onPressed: () =>
                  controller.applySettings(settings.withChatText(roomId, 1.0)),
              label: words.chatTextNormal,
            ),
          ),
          GlassSlider(
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

/// A chat drawn like the real one, with the same sizes: its top bar, a
/// message each way and the input row. Every button has its own size, so
/// changing one button changes only that button.
class AccessibilityPreview extends StatelessWidget {
  const AccessibilityPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final labels = AppearanceL10n.of(context);
    final settings = AccessibilityScope.of(context);
    final (:toolbarHeight, :leadingWidth) = ChatAppBarTitle.barSize(context);

    return Container(
      key: const Key('accessibility_preview'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      // Only a picture of the chat: its buttons do nothing.
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            AppBar(
              primary: false,
              automaticallyImplyLeading: false,
              toolbarHeight: toolbarHeight,
              leadingWidth: leadingWidth,
              actionsPadding: settings.buttonLabels
                  ? const EdgeInsetsDirectional.only(end: 8)
                  : null,
              titleSpacing: 0,
              shape: Border(bottom: BorderSide(color: theme.dividerColor)),
              leading: Center(
                child: AccessibilityIconButtons(
                  button: AccessibleButton.back,
                  child: BackButton(onPressed: () {}),
                ),
              ),
              title: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    // Like the chat: the name matters more than the avatar.
                    if (constraints.maxWidth >= 40 + 12 + 48) ...[
                      Avatar(name: l10n.previewChatName, size: 40),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        l10n.previewChatName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: settings.appBarTitle(17),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                AccessibilityIconButtons(
                  button: AccessibleButton.menu,
                  child: IconButton(
                    onPressed: () {},
                    icon: LabeledIcon(
                      icon: Icon(Icons.adaptive.more),
                      label: labels.labelMenu,
                    ),
                  ),
                ),
              ],
            ),
            AccessibilityTextScale(
              category: ScaleCategory.messageText,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: .stretch,
                  spacing: 8,
                  children: [
                    _PreviewMessage(text: l10n.previewMessage, own: false),
                    _PreviewMessage(text: l10n.previewReply, own: true),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: AccessibilityIconButtons(child: _PreviewInputRow()),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text message like in the chat: the bubble shape, the time inside of
/// it, and the sender's avatar next to the messages of others.
class _PreviewMessage extends StatelessWidget {
  final String text;
  final bool own;

  const _PreviewMessage({required this.text, required this.own});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AccessibilityScope.of(context);
    final avatarSize = settings.avatar(36);
    final metaColor = own
        ? theme.bubbleAccentColor
        : theme.otherBubbleAccentColor;
    final bubble = Container(
      decoration: ShapeDecoration(
        color: own ? theme.bubbleColor : theme.otherBubbleColor,
        shape: MessageBubbleBorder(
          ownMessage: own,
          cupertino: theme.cupertinoStyle,
          tail: theme.cupertinoStyle,
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6) *
                settings.messageScale(null),
            child: Text(
              text,
              style: TextStyle(
                color: own ? theme.onBubbleColor : theme.onOtherBubbleColor,
                fontSize: AppConfig.messageFontSize,
                // 1.25 is the line height messages are drawn with.
                height: settings.lineHeight ?? 1.25,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 10, bottom: 5),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: MaterialLocalizations.of(
                      context,
                    ).formatTimeOfDay(const TimeOfDay(hour: 9, minute: 41)),
                  ),
                  if (own)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(Icons.done_all, size: 16, color: metaColor),
                      ),
                    ),
                ],
              ),
              style: TextStyle(fontSize: 12, color: metaColor),
            ),
          ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: .end,
      mainAxisAlignment: own ? .end : .start,
      children: [
        if (!own)
          Avatar(
            name: PersonalizationL10n.of(context).previewChatName,
            size: avatarSize,
          ),
        Flexible(
          child: Padding(
            padding: EdgeInsets.only(
              left: own ? avatarSize + 16 : 2,
              right: own ? 0 : avatarSize + 16,
            ),
            child: bubble,
          ),
        ),
      ],
    );
  }
}

/// The input row of the chat ([ChatInputRow]) with an empty field, drawn
/// with the same sizes, colors and places of its buttons.
class _PreviewInputRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final labels = AppearanceL10n.of(context);
    final a11y = AccessibilityScope.of(context);
    final cupertino = theme.cupertinoStyle;
    final glass = PlatformInfos.supportsLiquidGlass;
    final height = a11y.buttonBox(ChatInputRow.height);
    double box(AccessibleButton button) => a11y.buttonBox(48, button);
    double slot(AccessibleButton button, String label) =>
        max(box(button), AccessibilityButtonLabel.widthOf(context, label));
    final labelHeight = AccessibilityButtonLabel.heightOf(context);
    final rowHeight = [
      height,
      for (final b in const [
        AccessibleButton.emoji,
        AccessibleButton.attach,
        AccessibleButton.send,
        AccessibleButton.microphone,
      ])
        box(b) + labelHeight,
    ].reduce(max);
    final gapWidth = max(0.0, a11y.spacing(8) - 8);
    final gap = SizedBox(width: gapWidth);
    // An empty chat field shows the microphone where it can record. The send
    // button shows instead when only its size was changed, so that change is
    // visible too.
    final showSend =
        !PlatformInfos.platformCanRecord ||
        (a11y[ScaleCategory.sendButton] != 1.0 &&
            a11y[ScaleCategory.microphoneButton] == 1.0);
    final sendLabel = showSend ? labels.labelSend : labels.labelMicrophone;
    final sendKind = showSend
        ? AccessibleButton.send
        : AccessibleButton.microphone;
    final sendWidth = max(height, slot(sendKind, sendLabel));
    final emojiWidth = slot(AccessibleButton.emoji, labels.labelEmoji);
    final attachWidth = slot(AccessibleButton.attach, labels.labelAttach);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Like the chat: big buttons shrink so the field keeps this width.
        const minFieldWidth = 120.0;
        final buttonsWidth =
            attachWidth +
            emojiWidth +
            sendWidth +
            gapWidth * (cupertino ? 2 : 3);
        final fit = constraints.hasBoundedWidth
            ? ((constraints.maxWidth - minFieldWidth) / buttonsWidth).clamp(
                0.0,
                1.0,
              )
            : 1.0;
        Widget button(
          AccessibleButton kind,
          String label,
          double width,
          Widget child, {
          Color? labelColor,
        }) => Container(
          key: Key('accessibility_preview_${kind.name}'),
          width: width * fit,
          height: rowHeight,
          alignment: Alignment.center,
          child: AccessibilityIconButtons(
            button: kind,
            child: AccessibilityButtonLabel(
              label: label,
              color: labelColor,
              child: FittedBox(fit: BoxFit.scaleDown, child: child),
            ),
          ),
        );

        final attachIcon = IconButton(
          onPressed: () {},
          icon: Icon(cupertino ? CupertinoIcons.add : Icons.add),
          color: theme.colorScheme.onSurfaceVariant,
          style: glass
              ? null
              : IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                ),
        );
        final attachButton = button(
          AccessibleButton.attach,
          labels.labelAttach,
          attachWidth,
          glass
              ? LiquidGlass(
                  borderRadius: BorderRadius.circular(
                    box(AccessibleButton.attach) / 2,
                  ),
                  child: attachIcon,
                )
              : attachIcon,
        );
        final emojiButton = button(
          AccessibleButton.emoji,
          labels.labelEmoji,
          emojiWidth,
          IconButton(
            onPressed: () {},
            color: theme.colorScheme.onSurfaceVariant,
            icon: Icon(
              cupertino ? CupertinoIcons.smiley : Icons.emoji_emotions_outlined,
            ),
          ),
        );
        final sendButton = showSend
            ? button(
                AccessibleButton.send,
                labels.labelSend,
                sendWidth,
                labelColor: theme.colorScheme.primary,
                IconButton(
                  onPressed: () {},
                  color: theme.colorScheme.onPrimary,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                  ),
                  icon: Icon(cupertino ? CupertinoIcons.arrow_up : Icons.send),
                ),
              )
            : button(
                AccessibleButton.microphone,
                labels.labelMicrophone,
                sendWidth,
                IconButton(
                  onPressed: () {},
                  color: cupertino
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onPrimaryContainer,
                  style: cupertino
                      ? null
                      : IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.primaryContainer,
                        ),
                  icon: Icon(
                    cupertino ? CupertinoIcons.mic : Icons.mic_none_outlined,
                  ),
                ),
              );
        // iOS keeps the send button inside of the field, like Messages.
        final fieldRadius = BorderRadius.circular(rowHeight / 2);
        final fieldRow = Container(
          constraints: BoxConstraints(minHeight: rowHeight),
          decoration: BoxDecoration(
            color: cupertino ? null : theme.colorScheme.surfaceContainerHigh,
            border: cupertino && !glass
                ? Border.all(color: theme.colorScheme.outlineVariant)
                : null,
            borderRadius: fieldRadius,
          ),
          child: Row(
            crossAxisAlignment: .end,
            children: [
              emojiButton,
              gap,
              Expanded(
                child: Container(
                  constraints: BoxConstraints(minHeight: rowHeight),
                  alignment: AlignmentDirectional.centerStart,
                  padding: const EdgeInsets.fromLTRB(6, 5, 6, 8),
                  child: Text(
                    l10n.typeMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: AccessibilityTextScale.inputTextScaler(context),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (cupertino) sendButton,
            ],
          ),
        );
        return Row(
          crossAxisAlignment: .end,
          children: [
            attachButton,
            gap,
            Expanded(
              child: glass
                  ? LiquidGlass(borderRadius: fieldRadius, child: fieldRow)
                  : fieldRow,
            ),
            if (!cupertino) ...[gap, sendButton],
          ],
        );
      },
    );
  }
}
