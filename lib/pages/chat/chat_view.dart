// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_list_tile.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat/chat_background.dart';
import 'package:fluffychat/pages/chat/chat_event_list.dart';
import 'package:fluffychat/pages/chat/pinned_events.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/personalization/signals/tracked_target.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/bubble_color_picker.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/pulsating_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/stream_extension.dart';
import 'chat_emoji_picker.dart';
import 'chat_input_row.dart';

enum _EventContextAction { report }

/// An action of the bar while messages are selected.
typedef _SelectionAction = ({
  IconData icon,
  String label,
  String tooltip,
  VoidCallback onPressed,
});

class ChatView extends StatelessWidget {
  final ChatController controller;

  const ChatView(this.controller, {super.key});

  /// The actions of the bar while messages are selected. Those that do not
  /// fit next to the close button and the count move into the "more" menu:
  /// reply in thread first, then edit, copy and delete.
  List<Widget> _selectionActions(BuildContext context, double leadingWidth) {
    final l10n = L10n.of(context);
    final a11y = AccessibilityScope.of(context);
    final selected = controller.selectedEvents;
    final single = selected.length == 1;
    final edit = controller.canEditSelectedEvents
        ? (
            icon: Icons.edit_outlined,
            label: l10n.edit,
            tooltip: l10n.edit,
            onPressed: controller.editSelectedEventAction,
          )
        : null;
    final thread =
        single &&
            controller.activeThreadId == null &&
            controller.room.canSendDefaultMessages
        ? (
            icon: Icons.message_outlined,
            label: l10n.replyInThread,
            tooltip: l10n.replyInThread,
            onPressed: () => controller.enterThread(selected.single.eventId),
          )
        : null;
    final copy = (
      icon: Icons.copy_outlined,
      label: l10n.copy,
      tooltip: l10n.copyToClipboard,
      onPressed: controller.copyEventsAction,
    );
    final delete = controller.canRedactSelectedEvents
        ? (
            icon: Icons.delete_outlined,
            label: l10n.delete,
            tooltip: l10n.redactMessage,
            onPressed: controller.redactEventsAction,
          )
        : null;
    final shown = <_SelectionAction>[?edit, ?thread, copy, ?delete];
    final hasMenuItems =
        single &&
        (controller.canPinSelectedEvents ||
            controller.canSaveSelectedEvent ||
            selected.single.status.isSent);

    // The width of an icon button: its icon and padding, its minimum touch
    // target, and its label, which shrinks past 72 (see LabeledIcon).
    double buttonWidth(String label) => [
      a11y.icon() + 16,
      40 * a11y.touchTargetScale,
      if (a11y.buttonLabels)
        min(
              AccessibilityButtonLabel.widthOf(context, label) - 8,
              72 * a11y.touchTargetScale,
            ) +
            16,
    ].reduce(max);
    final available =
        MediaQuery.sizeOf(context).width -
        leadingWidth -
        // The count of selected messages and the end padding of the bar.
        MediaQuery.textScalerOf(context).scale(48) -
        (a11y.buttonLabels ? 8 : 0);
    double needed(bool menu) =>
        shown.fold(0.0, (sum, a) => sum + buttonWidth(a.label)) +
        (menu ? buttonWidth(l10n.more) : 0);
    final moved = <_SelectionAction>[];
    for (final action in [?thread, ?edit, copy, ?delete]) {
      if (needed(hasMenuItems || moved.isNotEmpty) <= available) break;
      shown.remove(action);
      moved.add(action);
    }

    PopupMenuItem<_EventContextAction> menuItem(
      IconData icon,
      String text, {
      VoidCallback? onTap,
      _EventContextAction? value,
      Color? color,
    }) => PopupMenuItem(
      onTap: onTap,
      value: value,
      child: Row(
        mainAxisSize: .min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Flexible(child: Text(text)),
        ],
      ),
    );

    return [
      for (final action in shown)
        IconButton(
          icon: LabeledIcon(icon: Icon(action.icon), label: action.label),
          tooltip: action.tooltip,
          onPressed: action.onPressed,
        ),
      if (hasMenuItems || moved.isNotEmpty)
        PopupMenuButton<_EventContextAction>(
          useRootNavigator: true,
          icon: LabeledIcon(icon: Icon(Icons.adaptive.more), label: l10n.more),
          onSelected: (action) {
            switch (action) {
              case _EventContextAction.report:
                controller.reportEventAction();
                break;
            }
          },
          itemBuilder: (context) => [
            for (final action in moved)
              menuItem(action.icon, action.tooltip, onTap: action.onPressed),
            if (controller.canPinSelectedEvents)
              menuItem(
                controller.isSelectedEventPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                controller.isSelectedEventPinned
                    ? l10n.unpinMessage
                    : l10n.pinMessage,
                onTap: controller.pinEvent,
              ),
            if (controller.canSaveSelectedEvent)
              menuItem(
                Icons.download_outlined,
                l10n.downloadFile,
                onTap: () => controller.saveSelectedEvent(context),
              ),
            if (single && selected.single.status.isSent)
              menuItem(
                Icons.shield_outlined,
                l10n.reportMessage,
                value: _EventContextAction.report,
                color: Colors.red,
              ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActiveGroupCall = controller.room.hasActiveMatrixRtcCall;

    final scrollUpBannerEventId = controller.scrollUpBannerEventId;

    // Like Messages on iOS 26, the glass field floats above the messages
    // without a bar. Everything else down there needs the bar behind it.
    final floatingInput =
        PlatformInfos.supportsLiquidGlass &&
        controller.selectedEvents.isEmpty &&
        !controller.showEmojiPicker &&
        !controller.room.isExtinct &&
        controller.room.canSendDefaultMessages &&
        controller.room.membership == Membership.join &&
        controller.room.isAbandonedDMRoom != true &&
        controller.room.otherPartyCanReceiveMessages;

    return PopScope(
      canPop:
          controller.selectedEvents.isEmpty &&
          !controller.showEmojiPicker &&
          controller.activeThreadId == null,
      onPopInvokedWithResult: (pop, _) async {
        if (pop) return;
        if (controller.selectedEvents.isNotEmpty) {
          controller.clearSelectedEvents();
        } else if (controller.showEmojiPicker) {
          controller.emojiPickerAction();
        } else if (controller.activeThreadId != null) {
          controller.closeThread();
        }
      },
      child: StreamBuilder(
        stream: controller.room.client.onRoomState.stream
            .where((update) => update.roomId == controller.room.id)
            .rateLimit(const Duration(seconds: 1)),
        builder: (context, snapshot) => FutureBuilder(
          future: controller.loadTimelineFuture,
          builder: (BuildContext context, snapshot) {
            var appbarBottomHeight = 0.0;
            final activeThreadId = controller.activeThreadId;
            if (activeThreadId != null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            if (controller.room.pinnedEventIds.isNotEmpty &&
                activeThreadId == null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            if (scrollUpBannerEventId != null && activeThreadId == null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            // The back and menu buttons can carry a label under them.
            final a11y = AccessibilityScope.of(context);
            final labeledBarHeight =
                max(
                  a11y.buttonBox(48, AccessibleButton.back),
                  a11y.buttonBox(48, AccessibleButton.menu),
                ) +
                AccessibilityButtonLabel.heightOf(context);
            final themeBarHeight = theme.appBarTheme.toolbarHeight ?? 56;
            final labelsOn = a11y.buttonLabels;
            // Room for the label under the back button.
            final leadingWidth = labelsOn
                ? max(
                    a11y.buttonBox(56, AccessibleButton.back),
                    // The label is inside the button, past its padding.
                    AccessibilityButtonLabel.widthOf(
                          context,
                          MaterialLocalizations.of(context).backButtonTooltip,
                        ) +
                        8,
                  )
                : theme.appBarTheme.leadingWidth ?? kToolbarHeight;
            return Scaffold(
              key: Key('chat_page'),
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                toolbarHeight: labeledBarHeight > themeBarHeight
                    ? labeledBarHeight
                    : null,
                leadingWidth: leadingWidth,
                actionsPadding: labelsOn
                    ? const EdgeInsetsDirectional.only(end: 8)
                    : null,
                shape: FluffyThemes.isColumnMode(context)
                    ? Border(
                        bottom: BorderSide(color: theme.dividerColor, width: 1),
                      )
                    : null,
                actionsIconTheme: IconThemeData(
                  color: controller.selectedEvents.isEmpty
                      ? null
                      : theme.colorScheme.onTertiaryContainer,
                ),
                backgroundColor: controller.selectedEvents.isEmpty
                    ? controller.activeThreadId != null
                          ? theme.colorScheme.secondaryContainer
                          : theme.colorScheme.surface.withAlpha(240)
                    : theme.colorScheme.tertiaryContainer,
                automaticallyImplyLeading: false,
                leading: controller.selectMode
                    ? IconButton(
                        icon: LabeledIcon(
                          icon: const Icon(Icons.close),
                          label: L10n.of(context).close,
                        ),
                        onPressed: controller.clearSelectedEvents,
                        tooltip: L10n.of(context).close,
                        color: theme.colorScheme.onTertiaryContainer,
                      )
                    : activeThreadId != null
                    ? IconButton(
                        icon: LabeledIcon(
                          icon: const Icon(Icons.close),
                          label: L10n.of(context).close,
                        ),
                        onPressed: controller.closeThread,
                        tooltip: L10n.of(context).backToMainChat,
                        color: theme.colorScheme.onSecondaryContainer,
                      )
                    : FluffyThemes.isColumnMode(context)
                    ? null
                    : Center(
                        // The theme puts the label under its icon.
                        child: AccessibilityIconButtons(
                          button: AccessibleButton.back,
                          child: const TrackedTarget(
                            id: 'back_button',
                            kind: TargetKind.button,
                            child: BackButton(),
                          ),
                        ),
                      ),
                titleSpacing: FluffyThemes.isColumnMode(context) ? 24 : 0,
                title: ChatAppBarTitle(controller),
                actions: [
                  if (controller.selectMode)
                    ..._selectionActions(context, leadingWidth)
                  else if (!controller.room.isArchived) ...[
                    if (hasActiveGroupCall)
                      PulsatingWidget(
                        color: theme.colorScheme.error,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: TextButton.icon(
                            icon: Icon(switch (controller
                                .room
                                .activeMatrixRtcCallIntent) {
                              .voice => Icons.video_call_outlined,
                              _ => Icons.mic_outlined,
                            }),
                            label: Text(
                              controller.room
                                  .getActiveMatrixRtcMembers()
                                  .length
                                  .toString(),
                            ),
                            onPressed:
                                controller.room.hasPermissionForMatrixRtcCall
                                ? controller.startOrJoinVideoCall
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                              foregroundColor: theme.colorScheme.onError,
                            ),
                          ),
                        ),
                      )
                    else if (controller.room.hasPermissionForMatrixRtcCall &&
                        controller.supportLiveKitCalls)
                      IconButton(
                        icon: LabeledIcon(
                          icon: const Icon(Icons.call_outlined),
                          label: L10n.of(context).startCall,
                        ),
                        tooltip: L10n.of(context).startCall,
                        onPressed: controller.startOrJoinVideoCall,
                      ),
                    // The menu puts its label under its icon.
                    AccessibilityIconButtons(
                      button: AccessibleButton.menu,
                      child: ChatSettingsPopupMenu(controller.room, true),
                    ),
                  ],
                ],
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(appbarBottomHeight),
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      PinnedEvents(controller),
                      if (activeThreadId != null)
                        SizedBox(
                          height: ChatAppBarListTile.fixedHeight,
                          child: Center(
                            child: TextButton.icon(
                              onPressed: () =>
                                  controller.scrollToEventId(activeThreadId),
                              icon: const Icon(Icons.message),
                              label: Text(L10n.of(context).replyInThread),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    theme.colorScheme.onSecondaryContainer,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (scrollUpBannerEventId != null &&
                          activeThreadId == null)
                        ChatAppBarListTile(
                          leading: IconButton(
                            color: theme.colorScheme.onSurfaceVariant,
                            icon: const Icon(Icons.close),
                            tooltip: L10n.of(context).close,
                            onPressed: () {
                              controller.discardScrollUpBannerEventId();
                              controller.setReadMarker();
                            },
                          ),
                          title: L10n.of(context).jumpToLastReadMessage,
                          trailing: TextButton(
                            onPressed: () {
                              controller.scrollToEventId(scrollUpBannerEventId);
                              controller.discardScrollUpBannerEventId();
                            },
                            child: Text(L10n.of(context).jump),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              floatingActionButton:
                  controller.showScrollDownButton &&
                      controller.selectedEvents.isEmpty
                  ? Padding(
                      // Above the input bar, however tall its labels are.
                      padding: EdgeInsets.only(
                        bottom: controller.inputBarHeight ?? 56,
                      ),
                      child: FloatingActionButton(
                        onPressed: controller.scrollDown,
                        heroTag: null,
                        mini: true,
                        backgroundColor: theme.colorScheme.surface,
                        foregroundColor: theme.colorScheme.onSurface,
                        child: const Icon(Icons.arrow_downward_outlined),
                      ),
                    )
                  : null,
              body: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (SizeChangedLayoutNotification notification) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => controller.updateInputBarHeight(),
                  );
                  return true;
                },
                child: DropTarget(
                  onDragDone: controller.onDragDone,
                  onDragEntered: controller.onDragEntered,
                  onDragExited: controller.onDragExited,
                  child: SafeArea(
                    top: false,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: StreamBuilder(
                            stream:
                                controller.room.client.onChatWallpaperChanged,
                            builder: (context, _) => ChatWallpaperBackground(
                              wallpaper: controller.room.wallpaper,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: controller.clearSingleSelectedEvent,
                          child: TrackedTarget(
                            id: 'chat_timeline',
                            kind: TargetKind.text,
                            child: BubbleColorScope(
                              room: controller.room,
                              child: ChatEventList(controller: controller),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: SizeChangedLayoutNotifier(
                            // Like the bars of iOS, translucent above the
                            // messages scrolled under it.
                            child: ClipRect(
                              child: BackdropFilter(
                                enabled: theme.cupertinoStyle && !floatingInput,
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 20,
                                  sigmaY: 20,
                                ),
                                child: Container(
                                  key: controller.inputBarKey,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  color: floatingInput
                                      ? Colors.transparent
                                      : theme.cupertinoStyle
                                      ? theme.colorScheme.surface.withAlpha(215)
                                      : theme.colorScheme.surface,
                                  alignment: Alignment.center,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: FluffyThemes.maxTimelineWidth,
                                    ),
                                    child: controller.room.isExtinct
                                        ? ElevatedButton.icon(
                                            icon: const Icon(
                                              Icons.chevron_right,
                                            ),
                                            label: Text(
                                              L10n.of(context).enterNewChat,
                                            ),
                                            onPressed:
                                                controller.goToNewRoomAction,
                                          )
                                        : !controller
                                                  .room
                                                  .canSendDefaultMessages &&
                                              controller.room.membership !=
                                                  Membership.invite
                                        ? const SizedBox.shrink()
                                        : Material(
                                            clipBehavior: Clip.hardEdge,
                                            color:
                                                controller
                                                    .selectedEvents
                                                    .isNotEmpty
                                                ? theme
                                                      .colorScheme
                                                      .tertiaryContainer
                                                : Colors.transparent,
                                            child:
                                                controller.room.membership ==
                                                    .invite
                                                ? Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextButton.icon(
                                                          style: TextButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  16,
                                                                ),
                                                            foregroundColor:
                                                                theme
                                                                    .colorScheme
                                                                    .error,
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .cancel_outlined,
                                                          ),
                                                          onPressed: controller
                                                              .leaveChat,
                                                          label: Text(
                                                            L10n.of(
                                                              context,
                                                            ).decline,
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: TextButton.icon(
                                                          style: TextButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  16,
                                                                ),
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .check_outlined,
                                                          ),
                                                          onPressed: controller
                                                              .joinChat,
                                                          label: Text(
                                                            L10n.of(
                                                              context,
                                                            ).accept,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : controller
                                                          .room
                                                          .isAbandonedDMRoom ==
                                                      true
                                                ? Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextButton.icon(
                                                          style: TextButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  16,
                                                                ),
                                                            foregroundColor:
                                                                theme
                                                                    .colorScheme
                                                                    .error,
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .archive_outlined,
                                                          ),
                                                          onPressed: controller
                                                              .leaveChat,
                                                          label: Text(
                                                            L10n.of(
                                                              context,
                                                            ).leave,
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: TextButton.icon(
                                                          style: TextButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  16,
                                                                ),
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .forum_outlined,
                                                          ),
                                                          onPressed: controller
                                                              .recreateChat,
                                                          label: Text(
                                                            L10n.of(
                                                              context,
                                                            ).reopenChat,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : Column(
                                                    mainAxisSize: .min,
                                                    children: [
                                                      ReplyDisplay(controller),
                                                      AccessibilityIconButtons(
                                                        child: ChatInputRow(
                                                          controller,
                                                        ),
                                                      ),
                                                      ChatEmojiPicker(
                                                        controller,
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (controller.dragging)
                          Container(
                            color: theme.scaffoldBackgroundColor.withAlpha(230),
                            alignment: Alignment.center,
                            child: const Icon(Icons.upload_outlined, size: 100),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
