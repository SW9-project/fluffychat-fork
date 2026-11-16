// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/recording_input_row.dart';
import 'package:fluffychat/pages/chat/recording_view_model.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/appearance_l10n.dart';
import 'package:fluffychat/personalization/signals/tracked_target.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/liquid_glass.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import 'chat.dart';
import 'input_bar.dart';

class ChatInputRow extends StatelessWidget {
  final ChatController controller;

  static const double height = 56.0;

  const ChatInputRow(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textMessageOnly =
        controller.sendController.text.isNotEmpty ||
        controller.replyEvent != null ||
        controller.editEvent != null;

    if (!controller.room.otherPartyCanReceiveMessages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selectedTextButtonStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onTertiaryContainer,
    );

    final a11y = AccessibilityScope.of(context);
    final height = a11y.buttonBox(ChatInputRow.height);
    final buttonWidth = a11y.buttonBox(48);
    // Each button has its own size on top of the button size, and the row is
    // as high as its biggest button.
    double box(AccessibleButton button) => a11y.buttonBox(48, button);
    final rowHeight = [
      height,
      for (final b in const [
        AccessibleButton.emoji,
        AccessibleButton.attach,
        AccessibleButton.send,
        AccessibleButton.microphone,
      ])
        box(b),
    ].reduce(max);
    // Space between the buttons, by the spacing setting: none at normal,
    // up to 8 at twice the spacing. Less spacing comes from the density.
    final gap = SizedBox(width: max(0, a11y.spacing(8) - 8));
    final labels = AppearanceL10n.of(context);
    final cupertino = theme.cupertinoStyle;
    // Since iOS 26 the field and the add button float on Liquid Glass.
    final glass = PlatformInfos.supportsLiquidGlass;
    Widget glassCircle(Widget child) => glass
        ? LiquidGlass(
            borderRadius: BorderRadius.circular(
              box(AccessibleButton.attach) / 2,
            ),
            child: child,
          )
        : child;
    final l10n = L10n.of(context);
    // null separates groups in the Material menu.
    final addActions = <(AddPopupMenuActions, IconData, String)?>[
      if (PlatformInfos.isMobile)
        (
          AddPopupMenuActions.location,
          Icons.gps_fixed_outlined,
          l10n.shareLocation,
        ),
      (AddPopupMenuActions.poll, Icons.poll_outlined, l10n.startPoll),
      null,
      if (PlatformInfos.isMobile) ...[
        (
          AddPopupMenuActions.videoCamera,
          Icons.videocam_outlined,
          l10n.recordAVideo,
        ),
        (
          AddPopupMenuActions.photoCamera,
          Icons.camera_alt_outlined,
          l10n.takeAPhoto,
        ),
        null,
      ],
      (AddPopupMenuActions.video, Icons.movie_outlined, l10n.sendVideo),
      (AddPopupMenuActions.image, Icons.image_outlined, l10n.sendImage),
      (AddPopupMenuActions.file, Icons.attachment_outlined, l10n.sendFile),
    ];
    final isRecordButton =
        PlatformInfos.platformCanRecord &&
        !controller.sendController.text.isNotEmpty &&
        controller.editEvent == null;

    return RecordingViewModel(
      builder: (context, recordingViewModel) {
        if (recordingViewModel.isRecording) {
          return RecordingInputRow(
            state: recordingViewModel,
            onSend: controller.onVoiceMessageSend,
          );
        }
        final emojiButton = Container(
          height: rowHeight,
          width: box(AccessibleButton.emoji),
          alignment: Alignment.center,
          child: TrackedTarget(
            id: 'emoji_button',
            kind: TargetKind.button,
            child: _Button(
              button: AccessibleButton.emoji,
              label: labels.labelEmoji,
              child: IconButton(
                tooltip: L10n.of(context).emojis,
                color: theme.colorScheme.onSurfaceVariant,
                icon: Icon(switch ((controller.showEmojiPicker, cupertino)) {
                  (true, true) => CupertinoIcons.keyboard,
                  (true, false) => Icons.keyboard,
                  (false, true) => CupertinoIcons.smiley,
                  (false, false) => Icons.emoji_emotions_outlined,
                }, key: ValueKey(controller.showEmojiPicker)),
                onPressed: controller.emojiPickerAction,
              ),
            ),
          ),
        );
        final attachButton = AnimatedContainer(
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          width: textMessageOnly ? 0 : box(AccessibleButton.attach),
          height: rowHeight,
          alignment: Alignment.center,
          decoration: const BoxDecoration(),
          clipBehavior: Clip.hardEdge,
          child: TrackedTarget(
            id: 'attach_button',
            kind: TargetKind.button,
            child: _Button(
              button: AccessibleButton.attach,
              label: labels.labelAttach,
              // iOS shows an action sheet, other platforms a menu.
              child: PlatformInfos.isIOS
                  ? glassCircle(
                      IconButton(
                        icon: const Icon(CupertinoIcons.add),
                        color: theme.colorScheme.onSurfaceVariant,
                        style: glass
                            ? null
                            : IconButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHigh,
                              ),
                        onPressed: () async {
                          final action = await showModalActionPopup(
                            context: context,
                            cancelLabel: L10n.of(context).cancel,
                            actions: [
                              for (final a in addActions.nonNulls)
                                AdaptiveModalAction(label: a.$3, value: a.$1),
                            ],
                          );
                          if (action != null) {
                            controller.onAddPopupMenuButtonSelected(action);
                          }
                        },
                      ),
                    )
                  : PopupMenuButton<AddPopupMenuActions>(
                      useRootNavigator: true,
                      icon: Icon(cupertino ? CupertinoIcons.add : Icons.add),
                      iconColor: theme.colorScheme.onSurfaceVariant,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      ),
                      onSelected: controller.onAddPopupMenuButtonSelected,
                      itemBuilder: (BuildContext context) => [
                        for (final a in addActions)
                          a == null
                              ? const PopupMenuDivider()
                              : PopupMenuItem(
                                  value: a.$1,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          theme.colorScheme.onPrimaryContainer,
                                      foregroundColor:
                                          theme.colorScheme.primaryContainer,
                                      child: Icon(a.$2),
                                    ),
                                    title: Text(a.$3),
                                    contentPadding: const EdgeInsets.all(0),
                                  ),
                                ),
                      ],
                    ),
            ),
          ),
        );
        final sendButton = Container(
          height: rowHeight,
          width: max(
            height,
            box(
              isRecordButton
                  ? AccessibleButton.microphone
                  : AccessibleButton.send,
            ),
          ),
          alignment: Alignment.center,
          child: TrackedTarget(
            id: 'send_button',
            kind: TargetKind.button,
            child: isRecordButton
                ? HoverBuilder(
                    builder: (context, hovered) => _Button(
                      button: AccessibleButton.microphone,
                      label: labels.labelMicrophone,
                      child: IconButton(
                        tooltip: L10n.of(context).voiceMessage,
                        onPressed: hovered
                            ? () => recordingViewModel.startRecording(
                                controller.room,
                              )
                            : () => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  margin: EdgeInsets.only(
                                    bottom: height + 16,
                                    left: 16,
                                    right: 16,
                                    top: 16,
                                  ),
                                  showCloseIcon: true,
                                  content: Text(
                                    L10n.of(
                                      context,
                                    ).longPressToRecordVoiceMessage,
                                  ),
                                ),
                              ),
                        onLongPress: () =>
                            recordingViewModel.startRecording(controller.room),
                        color: cupertino
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onPrimaryContainer,
                        style: cupertino
                            ? null
                            : IconButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                              ),
                        icon: Icon(
                          cupertino
                              ? CupertinoIcons.mic
                              : hovered
                              ? Icons.mic
                              : Icons.mic_none_outlined,
                        ),
                      ),
                    ),
                  )
                : _Button(
                    button: AccessibleButton.send,
                    label: labels.labelSend,
                    color: theme.colorScheme.primary,
                    child: IconButton(
                      key: Key('send_button'),
                      tooltip: L10n.of(context).send,
                      onPressed: controller.send,
                      color: theme.colorScheme.onPrimary,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                      ),
                      icon: Icon(
                        cupertino ? CupertinoIcons.arrow_up : Icons.send,
                      ),
                    ),
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
              if (Matrix.of(context).isMultiAccount &&
                  Matrix.of(context).hasComplexBundles &&
                  Matrix.of(context).currentBundle!.length > 1)
                Container(
                  height: height,
                  width: buttonWidth,
                  alignment: Alignment.center,
                  child: _ChatAccountPicker(controller),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: InputBar(
                    room: controller.room,
                    minLines: 1,
                    maxLines: 8,
                    autofocus: !PlatformInfos.isMobile,
                    keyboardType: TextInputType.multiline,
                    textInputAction:
                        AppSettings.sendOnEnter.value == true &&
                            PlatformInfos.isMobile
                        ? TextInputAction.send
                        : null,
                    onSubmitted: controller.onInputBarSubmitted,
                    onSubmitImage: controller.sendImageFromClipBoard,
                    focusNode: controller.inputFocus,
                    controller: controller.sendController,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.only(
                        left: 6.0,
                        right: 6.0,
                        bottom: 6.0,
                        top: 3.0,
                      ),
                      counter: const SizedBox.shrink(),
                      hintText: controller.room.encrypted
                          ? L10n.of(context).encryptedMessage
                          : L10n.of(context).unencryptedMessage,
                      hintMaxLines: 1,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      filled: false,
                    ),
                    onChanged: controller.onInputBarChanged,
                    suggestionEmojis:
                        getDefaultEmojiLocale(
                          AppSettings.emojiSuggestionLocale.value.isNotEmpty
                              ? Locale(AppSettings.emojiSuggestionLocale.value)
                              : Localizations.localeOf(context),
                        ).fold(
                          [],
                          (emojis, category) => emojis..addAll(category.emoji),
                        ),
                  ),
                ),
              ),
              if (cupertino) sendButton,
            ],
          ),
        );
        final field = Expanded(
          child: glass
              ? LiquidGlass(borderRadius: fieldRadius, child: fieldRow)
              : fieldRow,
        );
        return Row(
          crossAxisAlignment: .end,
          mainAxisAlignment: .spaceBetween,
          children: controller.selectMode
              ? <Widget>[
                  if (controller.selectedEvents.every(
                    (event) => event.status == EventStatus.error,
                  ))
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: controller.deleteErrorEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.delete_forever_outlined),
                            Text(L10n.of(context).delete),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: selectedTextButtonStyle,
                        onPressed: controller.forwardEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.keyboard_arrow_left_outlined),
                            Text(L10n.of(context).forward),
                          ],
                        ),
                      ),
                    ),
                  controller.selectedEvents.length == 1
                      ? controller.selectedEvents.first
                                .getDisplayEvent(controller.timeline!)
                                .status
                                .isSent
                            ? SizedBox(
                                height: height,
                                child: TextButton(
                                  style: selectedTextButtonStyle,
                                  onPressed: controller.replyAction,
                                  child: Row(
                                    children: <Widget>[
                                      Text(L10n.of(context).reply),
                                      const Icon(Icons.keyboard_arrow_right),
                                    ],
                                  ),
                                ),
                              )
                            : SizedBox(
                                height: height,
                                child: TextButton(
                                  style: selectedTextButtonStyle,
                                  onPressed: controller.sendAgainAction,
                                  child: Row(
                                    children: <Widget>[
                                      Text(L10n.of(context).tryToSendAgain),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.send_outlined, size: 16),
                                    ],
                                  ),
                                ),
                              )
                      : const SizedBox.shrink(),
                ]
              : <Widget>[
                  attachButton,
                  if (!textMessageOnly) gap,
                  field,
                  if (!cupertino) ...[gap, sendButton],
                ],
        );
      },
    );
  }
}

class _ChatAccountPicker extends StatelessWidget {
  final ChatController controller;

  const _ChatAccountPicker(this.controller);

  void _popupMenuButtonSelected(String mxid, BuildContext context) {
    final client = Matrix.of(
      context,
    ).currentBundle!.firstWhere((cl) => cl!.userID == mxid, orElse: () => null);
    if (client == null) {
      Logs().w('Attempted to switch to a non-existing client $mxid');
      return;
    }
    controller.setSendingClient(client);
  }

  @override
  Widget build(BuildContext context) {
    final clients = controller.currentRoomBundle;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: FutureBuilder<Profile>(
        future: controller.sendingClient.fetchOwnProfile(),
        builder: (context, snapshot) => PopupMenuButton<String>(
          useRootNavigator: true,
          onSelected: (mxid) => _popupMenuButtonSelected(mxid, context),
          itemBuilder: (BuildContext context) => clients
              .map(
                (client) => PopupMenuItem(
                  value: client!.userID,
                  child: FutureBuilder<Profile>(
                    future: client.fetchOwnProfile(),
                    builder: (context, snapshot) => ListTile(
                      leading: Avatar(
                        mxContent: snapshot.data?.avatarUrl,
                        name:
                            snapshot.data?.displayName ??
                            client.userID!.localpart,
                        size: 20,
                      ),
                      title: Text(snapshot.data?.displayName ?? client.userID!),
                      contentPadding: const EdgeInsets.all(0),
                    ),
                  ),
                ),
              )
              .toList(),
          child: Avatar(
            mxContent: snapshot.data?.avatarUrl,
            name:
                snapshot.data?.displayName ??
                Matrix.of(context).client.userID!.localpart,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// One button of the input row: its own icon size, and its label under it
/// while button labels are on.
class _Button extends StatelessWidget {
  final AccessibleButton button;
  final String label;
  final Color? color;
  final Widget child;

  const _Button({
    required this.button,
    required this.label,
    required this.child,
    this.color,
  });

  @override
  Widget build(BuildContext context) => AccessibilityIconButtons(
    button: button,
    child: AccessibilityButtonLabel(label: label, color: color, child: child),
  );
}
