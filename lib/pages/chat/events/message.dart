// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/event_read_extension.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/member_actions_popup_menu_button.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../config/app_config.dart';
import '../sticker_picker_dialog.dart';
import 'message_content.dart';
import 'message_reactions.dart';
import 'reply_content.dart';
import 'state_message.dart';
import 'swipe_to_reply.dart';

class Message extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? previousEvent;
  final bool displayReadMarker;
  final void Function(Event) onSelect;
  final void Function(Event) onInfoTab;
  final void Function(String) scrollToEventId;
  final void Function() onSwipe;
  final void Function() onMention;
  final void Function() onEdit;
  final void Function(String eventId)? enterThread;
  final bool longPressSelect;
  final bool selected;
  final bool singleSelected;
  final Timeline timeline;
  final bool highlightMarker;
  final bool animateIn;
  final bool wallpaperMode;
  final void Function()? onExpand;
  final bool isCollapsed;
  final Set<String> bigEmojis;

  const Message(
    this.event, {
    this.nextEvent,
    this.previousEvent,
    this.displayReadMarker = false,
    this.longPressSelect = false,
    required this.bigEmojis,
    required this.onSelect,
    required this.onInfoTab,
    required this.scrollToEventId,
    required this.onSwipe,
    this.selected = false,
    required this.onEdit,
    required this.singleSelected,
    required this.timeline,
    this.highlightMarker = false,
    this.animateIn = false,
    this.wallpaperMode = false,
    required this.onMention,
    this.onExpand,
    required this.enterThread,
    this.isCollapsed = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!{
      EventTypes.Message,
      EventTypes.Sticker,
      EventTypes.CallInvite,
      PollEventContent.startType,
    }.contains(event.type)) {
      if (event.type.startsWith('m.call.')) {
        return const SizedBox.shrink();
      }
      return StateMessage(event, onExpand: onExpand, isCollapsed: isCollapsed);
    }

    if (event.type == EventTypes.Message &&
        event.messageType == EventTypes.KeyVerificationRequest) {
      return StateMessage(event);
    }

    final client = Matrix.of(context).client;
    final ownMessage = event.senderId == client.userID;
    final alignment = ownMessage ? Alignment.topRight : Alignment.topLeft;

    final color = ownMessage ? theme.bubbleColor : theme.otherBubbleColor;

    final nextEventSameSender =
        nextEvent != null &&
        {EventTypes.Message, EventTypes.Sticker}.contains(nextEvent!.type) &&
        nextEvent!.senderId == event.senderId &&
        nextEvent!.originServerTs.sameEnvironment(event.originServerTs);

    final previousEventSameSender =
        previousEvent != null &&
        {
          EventTypes.Message,
          EventTypes.Sticker,
        }.contains(previousEvent!.type) &&
        previousEvent!.senderId == event.senderId &&
        previousEvent!.originServerTs.sameEnvironment(event.originServerTs);

    final textColor = ownMessage
        ? theme.onBubbleColor
        : theme.colorScheme.onSurface;

    final linkColor = theme.bubbleLinkColor;

    final rowMainAxisAlignment = ownMessage
        ? MainAxisAlignment.end
        : MainAxisAlignment.start;

    final displayEvent = event.getDisplayEvent(timeline);
    final avatarSize = AccessibilityScope.of(context).avatar(36);
    final noBubble =
        ({
          MessageTypes.Video,
          MessageTypes.Image,
          MessageTypes.Sticker,
        }.contains(event.messageType) &&
        event.fileDescription == null &&
        !event.redacted);
    final bubbleShape = MessageBubbleBorder(
      ownMessage: ownMessage,
      groupedAbove: nextEventSameSender,
      groupedBelow: previousEventSameSender,
      tail: !previousEventSameSender && !noBubble,
    );
    final borderRadius = bubbleShape.borderRadius;
    // Like in Telegram, avatars are only displayed in group chats next to
    // the last message of a group of messages from the same sender.
    final showAvatarColumn = !ownMessage && !event.room.isDirectChat;
    final displaySenderName =
        showAvatarColumn && !nextEventSameSender && !noBubble;

    final sentReactions = <String>{};
    if (singleSelected) {
      sentReactions.addAll(
        event
            .aggregatedEvents(timeline, RelationshipTypes.reaction)
            .where(
              (event) =>
                  event.senderId == event.room.client.userID &&
                  event.type == 'm.reaction',
            )
            .map(
              (event) => event.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'),
            )
            .whereType<String>(),
      );
    }

    final hasReactions = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );

    final threadChildren = event.aggregatedEvents(
      timeline,
      RelationshipTypes.thread,
    );
    final isEdited = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.edit,
    );

    final showReactionPicker =
        singleSelected && event.room.canSendDefaultMessages;

    final enterThread = this.enterThread;
    final sender = event.senderFromMemoryOrFallback;

    final wallpaperTextShadow = !wallpaperMode
        ? null
        : [
            Shadow(
              offset: Offset(0.0, 0.0),
              blurRadius: 2,
              color: theme.colorScheme.surface,
            ),
          ];
    final eventStateTextColor = theme.colorScheme.onSurface;

    return Center(
      child: SwipeToReply(
        key: ValueKey(event.transactionId ?? event.eventId),
        rightToLeft: AppSettings.swipeRightToLeftToReply.value,
        onReply: onSwipe,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.maxTimelineWidth,
          ),
          padding: EdgeInsets.only(
            left: 8.0,
            right: 8.0,
            top: nextEventSameSender ? 1.0 : 8.0,
            bottom: previousEventSameSender || previousEvent == null
                ? 1.0
                : 8.0,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: ownMessage ? .end : .start,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: InkWell(
                      hoverColor: longPressSelect ? Colors.transparent : null,
                      enableFeedback: !selected,
                      onTap: longPressSelect ? null : () => onSelect(event),
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius / 2,
                      ),
                      child: Material(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius / 2,
                        ),
                        color: selected || highlightMarker
                            ? theme.colorScheme.secondaryContainer.withAlpha(
                                128,
                              )
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: .end,
                    mainAxisAlignment: rowMainAxisAlignment,
                    children: [
                      if (longPressSelect && !event.redacted)
                        SizedBox(
                          height: avatarSize,
                          width: avatarSize,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: L10n.of(context).select,
                            icon: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                            ),
                            onPressed: () => onSelect(event),
                          ),
                        )
                      else if (showAvatarColumn && previousEventSameSender)
                        SizedBox(width: avatarSize)
                      else if (showAvatarColumn)
                        FutureBuilder<User?>(
                          future: event.fetchSenderUser(),
                          builder: (context, snapshot) {
                            final user = snapshot.data ?? sender;
                            return Avatar(
                              mxContent: user.avatarUrl,
                              name: user.calcDisplayname(),
                              onTap: () => showMemberActionsPopupMenu(
                                context: context,
                                user: user,
                                onMention: onMention,
                              ),
                              size: avatarSize,
                              presenceUserId: user.stateKey,
                              presenceBackgroundColor: Colors.transparent,
                            );
                          },
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          mainAxisSize: .min,
                          children: [
                            // Like in Telegram, the reaction picker is
                            // displayed above the selected message.
                            Align(
                              alignment: ownMessage
                                  ? Alignment.bottomRight
                                  : Alignment.bottomLeft,
                              child: AnimatedSize(
                                duration: FluffyThemes.animationDuration,
                                curve: FluffyThemes.animationCurve,
                                alignment: ownMessage
                                    ? Alignment.bottomRight
                                    : Alignment.bottomLeft,
                                child: showReactionPicker
                                    ? Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Material(
                                          elevation: 4,
                                          borderRadius: BorderRadius.circular(
                                            AppConfig.borderRadius,
                                          ),
                                          shadowColor: theme.colorScheme.surface
                                              .withAlpha(128),
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              mainAxisSize: .min,
                                              children: [
                                                ...AppConfig.defaultReactions.map(
                                                  (emoji) => IconButton(
                                                    padding: EdgeInsets.zero,
                                                    icon: Center(
                                                      child: Opacity(
                                                        opacity:
                                                            sentReactions
                                                                .contains(emoji)
                                                            ? 0.33
                                                            : 1,
                                                        child: Text(
                                                          emoji,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 20,
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                    onPressed:
                                                        sentReactions.contains(
                                                          emoji,
                                                        )
                                                        ? null
                                                        : () {
                                                            onSelect(event);
                                                            event.room
                                                                .sendReaction(
                                                                  event.eventId,
                                                                  emoji,
                                                                );
                                                          },
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.add_reaction_outlined,
                                                  ),
                                                  tooltip: L10n.of(
                                                    context,
                                                  ).customReaction,
                                                  onPressed: () async {
                                                    final emoji = await showAdaptiveBottomSheet<String>(
                                                      context: context,
                                                      builder: (context) => Scaffold(
                                                        appBar: AppBar(
                                                          title: Text(
                                                            L10n.of(
                                                              context,
                                                            ).customReaction,
                                                          ),
                                                          leading: CloseButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  context,
                                                                ).pop(null),
                                                          ),
                                                        ),
                                                        body: SizedBox(
                                                          height:
                                                              double.infinity,
                                                          child: DefaultTabController(
                                                            length: 2,
                                                            child: Column(
                                                              children: [
                                                                TabBar(
                                                                  tabs: [
                                                                    Tab(
                                                                      text: L10n.of(
                                                                        context,
                                                                      ).emojis,
                                                                    ),
                                                                    Tab(
                                                                      text: L10n.of(
                                                                        context,
                                                                      ).stickers,
                                                                    ),
                                                                  ],
                                                                ),
                                                                Expanded(
                                                                  child: TabBarView(
                                                                    children: [
                                                                      EmojiPicker(
                                                                        onEmojiSelected:
                                                                            (
                                                                              _,
                                                                              emoji,
                                                                            ) =>
                                                                                Navigator.of(
                                                                                  context,
                                                                                ).pop(
                                                                                  emoji.emoji,
                                                                                ),
                                                                        config: Config(
                                                                          locale: Localizations.localeOf(
                                                                            context,
                                                                          ),
                                                                          emojiViewConfig: const EmojiViewConfig(
                                                                            backgroundColor:
                                                                                Colors.transparent,
                                                                          ),
                                                                          bottomActionBarConfig: const BottomActionBarConfig(
                                                                            enabled:
                                                                                false,
                                                                          ),
                                                                          categoryViewConfig: CategoryViewConfig(
                                                                            initCategory:
                                                                                Category.SMILEYS,
                                                                            backspaceColor:
                                                                                theme.colorScheme.primary,
                                                                            iconColor: theme.colorScheme.primary.withAlpha(
                                                                              128,
                                                                            ),
                                                                            iconColorSelected:
                                                                                theme.colorScheme.primary,
                                                                            indicatorColor:
                                                                                theme.colorScheme.primary,
                                                                            backgroundColor:
                                                                                theme.colorScheme.surface,
                                                                          ),
                                                                          skinToneConfig: SkinToneConfig(
                                                                            dialogBackgroundColor: Color.lerp(
                                                                              theme.colorScheme.surface,
                                                                              theme.colorScheme.primaryContainer,
                                                                              0.75,
                                                                            )!,
                                                                            indicatorColor:
                                                                                theme.colorScheme.onSurface,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      StickerPickerDialog(
                                                                        room: event
                                                                            .room,
                                                                        usage: ImagePackUsage
                                                                            .emoticon,
                                                                        onSelected:
                                                                            (
                                                                              sticker,
                                                                            ) =>
                                                                                Navigator.of(
                                                                                  context,
                                                                                ).pop(
                                                                                  sticker.url.toString(),
                                                                                ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                    if (emoji == null) {
                                                      return;
                                                    }
                                                    if (sentReactions.contains(
                                                      emoji,
                                                    )) {
                                                      return;
                                                    }
                                                    onSelect(event);

                                                    await event.room
                                                        .sendReaction(
                                                          event.eventId,
                                                          emoji,
                                                        );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                            Container(
                              alignment: alignment,
                              padding: EdgeInsets.only(
                                left: ownMessage ? avatarSize + 16 : 2,
                                right: ownMessage ? 0 : avatarSize + 16,
                              ),
                              child: GestureDetector(
                                onDoubleTap:
                                    AppSettings.doubleTapToReact.value &&
                                        event.room.canSendDefaultMessages
                                    ? () {
                                        HapticFeedback.lightImpact();
                                        final emoji =
                                            AppSettings.doubleTapReaction.value;
                                        final existingReaction = event
                                            .aggregatedEvents(
                                              timeline,
                                              RelationshipTypes.reaction,
                                            )
                                            .firstWhereOrNull(
                                              (e) =>
                                                  e.senderId ==
                                                      event
                                                          .room
                                                          .client
                                                          .userID &&
                                                  e.content
                                                          .tryGetMap<
                                                            String,
                                                            Object?
                                                          >('m.relates_to')
                                                          ?.tryGet<String>(
                                                            'key',
                                                          ) ==
                                                      emoji,
                                            );
                                        if (existingReaction != null) {
                                          existingReaction.redactEvent();
                                        } else {
                                          event.room.sendReaction(
                                            event.eventId,
                                            emoji,
                                          );
                                        }
                                      }
                                    : null,
                                onLongPress: longPressSelect
                                    ? null
                                    : () {
                                        HapticFeedback.heavyImpact();
                                        onSelect(event);
                                      },
                                child: _AnimateIn(
                                  key: ValueKey(
                                    event.transactionId ?? event.eventId,
                                  ),
                                  animateIn: animateIn,
                                  child: Container(
                                    decoration: ShapeDecoration(
                                      color: noBubble
                                          ? Colors.transparent
                                          : color,
                                      shape: bubbleShape,
                                      shadows:
                                          noBubble ||
                                              theme.brightness ==
                                                  Brightness.dark
                                          ? null
                                          : const [
                                              BoxShadow(
                                                color: Color(0x26000000),
                                                blurRadius: 1,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxWidth:
                                            FluffyThemes.columnWidth * 1.5,
                                      ),
                                      child: Column(
                                        mainAxisSize: .min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          if (displaySenderName)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 12,
                                                right: 12,
                                                top: 6,
                                              ),
                                              child: Row(
                                                mainAxisSize: .min,
                                                children: [
                                                  if (sender.powerLevel.role !=
                                                      PowerLevelRole.user)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            right: 2.0,
                                                          ),
                                                      child: Icon(
                                                        sender
                                                                    .powerLevel
                                                                    .role ==
                                                                PowerLevelRole
                                                                    .moderator
                                                            ? Icons
                                                                  .add_moderator_outlined
                                                            : Icons
                                                                  .admin_panel_settings,
                                                        size: 14,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  Flexible(
                                                    child: FutureBuilder<User?>(
                                                      future: event
                                                          .fetchSenderUser(),
                                                      builder: (context, snapshot) {
                                                        final displayname =
                                                            snapshot.data
                                                                ?.calcDisplayname() ??
                                                            sender
                                                                .calcDisplayname();
                                                        return Text(
                                                          displayname,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                            color:
                                                                theme.brightness ==
                                                                    Brightness
                                                                        .light
                                                                ? displayname
                                                                      .colorScheme
                                                                      .primary
                                                                : displayname
                                                                      .colorScheme
                                                                      .primaryFixedDim,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (event.inReplyToEventId(
                                                includingFallback: false,
                                              ) !=
                                              null)
                                            FutureBuilder<Event?>(
                                              future: event.getReplyEvent(
                                                timeline,
                                              ),
                                              builder:
                                                  (
                                                    BuildContext context,
                                                    snapshot,
                                                  ) {
                                                    final replyEvent =
                                                        snapshot.hasData
                                                        ? snapshot.data!
                                                        : Event(
                                                            eventId:
                                                                event
                                                                    .inReplyToEventId() ??
                                                                '\$fake_event_id',
                                                            content: {
                                                              'msgtype':
                                                                  'm.text',
                                                              'body': '...',
                                                            },
                                                            senderId:
                                                                event.senderId,
                                                            type:
                                                                'm.room.message',
                                                            room: event.room,
                                                            status: EventStatus
                                                                .sent,
                                                            originServerTs:
                                                                DateTime.now(),
                                                          );
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            left: 8,
                                                            right: 8,
                                                            top: 6,
                                                          ),
                                                      child: Material(
                                                        color:
                                                            Colors.transparent,
                                                        borderRadius:
                                                            ReplyContent
                                                                .borderRadius,
                                                        child: InkWell(
                                                          borderRadius:
                                                              ReplyContent
                                                                  .borderRadius,
                                                          onTap: () =>
                                                              scrollToEventId(
                                                                replyEvent
                                                                    .eventId,
                                                              ),
                                                          child: AbsorbPointer(
                                                            child: ReplyContent(
                                                              replyEvent,
                                                              ownMessage:
                                                                  ownMessage,
                                                              timeline:
                                                                  timeline,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                            ),
                                          _MessageContentWithMeta(
                                            noBubble: noBubble,
                                            meta: _MessageMeta(
                                              event: displayEvent,
                                              ownMessage: ownMessage,
                                              isEdited: isEdited,
                                              selected: selected,
                                              color: noBubble
                                                  ? Colors.white
                                                  : ownMessage
                                                  ? theme.bubbleAccentColor
                                                  : theme
                                                        .otherBubbleAccentColor,
                                            ),
                                            child: _SelectableWhenSelected(
                                              selected: selected,
                                              child: MessageContent(
                                                displayEvent,
                                                textColor: textColor,
                                                linkColor: linkColor,
                                                onInfoTab: onInfoTab,
                                                borderRadius: borderRadius,
                                                timeline: timeline,
                                                selected: selected,
                                                bigEmojis: bigEmojis,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            AnimatedSize(
                              duration: FluffyThemes.animationDuration,
                              curve: FluffyThemes.animationCurve,
                              alignment: Alignment.bottomCenter,
                              child: !hasReactions
                                  ? const SizedBox.shrink()
                                  : Container(
                                      alignment: ownMessage
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      padding: EdgeInsets.only(
                                        top: 2.0,
                                        left: ownMessage ? 0 : 8.0,
                                        right: ownMessage
                                            ? MessageBubbleBorder.tailWidth
                                            : 12.0,
                                      ),
                                      child: MessageReactions(event, timeline),
                                    ),
                            ),
                            if (event.status == EventStatus.error ||
                                (event.status == EventStatus.sending &&
                                    event.fileSendingStatus != null))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment: ownMessage ? .end : .start,
                                  children: [
                                    if (event.status == EventStatus.error)
                                      Text(
                                        L10n.of(context).couldNotBeSent,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.error,
                                          shadows: wallpaperTextShadow,
                                        ),
                                      )
                                    else
                                      Text(
                                        switch (event.fileSendingStatus) {
                                          null => L10n.of(context).sending,
                                          FileSendingStatus
                                              .generatingThumbnail =>
                                            L10n.of(
                                              context,
                                            ).generatingThumbnail,
                                          FileSendingStatus.encrypting =>
                                            L10n.of(context).encrypting,
                                          FileSendingStatus.uploading =>
                                            L10n.of(context).uploading,
                                        },
                                        style: TextStyle(
                                          color: eventStateTextColor,
                                          fontSize: 11,
                                          shadows: wallpaperTextShadow,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (enterThread != null)
                AnimatedSize(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  alignment: Alignment.bottomCenter,
                  child: threadChildren.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: EdgeInsets.only(
                            top: 2.0,
                            bottom: 8.0,
                            left: avatarSize + 8,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: FluffyThemes.columnWidth * 1.5,
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                foregroundColor:
                                    theme.colorScheme.onSecondaryContainer,
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                              ),
                              onPressed: () => enterThread(event.eventId),
                              icon: const Icon(Icons.message),
                              label: Text(
                                '${L10n.of(context).countReplies(threadChildren.length)} | ${threadChildren.first.calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)), withSenderNamePrefix: true)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                ),
              if (displayReadMarker)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 12.0),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: theme.colorScheme.surface.withAlpha(200),
                  alignment: Alignment.center,
                  child: Text(
                    L10n.of(context).readUpToHere,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Like in Telegram, the text of a message can only be selected while the
/// message is selected, and only by starting on the text, not anywhere in the
/// timeline. The [GlobalKey] moves [child] into the [SelectionArea] instead of
/// rebuilding it, so images and players don't reload.
class _SelectableWhenSelected extends StatefulWidget {
  final bool selected;
  final Widget child;

  const _SelectableWhenSelected({required this.selected, required this.child});

  @override
  State<_SelectableWhenSelected> createState() =>
      _SelectableWhenSelectedState();
}

class _SelectableWhenSelectedState extends State<_SelectableWhenSelected> {
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (!widget.selected) return child;
    return SelectionArea(child: child);
  }
}

/// Telegram like bubble with a small tail at the bottom of the last message
/// in a group of messages from the same sender. The space for the tail is
/// always reserved so that all bubbles of a group are aligned.
class MessageBubbleBorder extends ShapeBorder {
  final bool ownMessage;
  final bool groupedAbove;
  final bool groupedBelow;
  final bool tail;

  const MessageBubbleBorder({
    required this.ownMessage,
    this.groupedAbove = false,
    this.groupedBelow = false,
    this.tail = false,
  });

  static const double tailWidth = 6.0;
  static const Radius _radius = Radius.circular(16);
  static const Radius _groupedRadius = Radius.circular(6);

  BorderRadius get borderRadius {
    final tailSideTop = groupedAbove ? _groupedRadius : _radius;
    final tailSideBottom = tail
        ? Radius.zero
        : groupedBelow
        ? _groupedRadius
        : _radius;
    return ownMessage
        ? BorderRadius.only(
            topLeft: _radius,
            bottomLeft: _radius,
            topRight: tailSideTop,
            bottomRight: tailSideBottom,
          )
        : BorderRadius.only(
            topLeft: tailSideTop,
            bottomLeft: tailSideBottom,
            topRight: _radius,
            bottomRight: _radius,
          );
  }

  @override
  EdgeInsetsGeometry get dimensions => ownMessage
      ? const EdgeInsets.only(right: tailWidth)
      : const EdgeInsets.only(left: tailWidth);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = ownMessage
        ? Rect.fromLTRB(
            rect.left,
            rect.top,
            rect.right - tailWidth,
            rect.bottom,
          )
        : Rect.fromLTRB(
            rect.left + tailWidth,
            rect.top,
            rect.right,
            rect.bottom,
          );
    final path = Path()..addRRect(borderRadius.toRRect(body));
    if (!tail) return path;

    final tailHeight = min(14.0, body.height / 2);
    final edgeX = ownMessage ? body.right : body.left;
    final tipX = ownMessage ? rect.right : rect.left;
    return path
      ..moveTo(edgeX, body.bottom - tailHeight)
      ..quadraticBezierTo(edgeX, body.bottom - 3, tipX, body.bottom)
      ..lineTo(edgeX, body.bottom)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) =>
      other is MessageBubbleBorder &&
      other.ownMessage == ownMessage &&
      other.groupedAbove == groupedAbove &&
      other.groupedBelow == groupedBelow &&
      other.tail == tail;

  @override
  int get hashCode => Object.hash(ownMessage, groupedAbove, groupedBelow, tail);
}

/// Places the time and status of a message inside of the bubble like in
/// Telegram: Next to the content if there is enough space, otherwise in a
/// new line. Images without a bubble get the time on top of them.
class _MessageContentWithMeta extends StatelessWidget {
  final Widget child;
  final Widget meta;
  final bool noBubble;

  const _MessageContentWithMeta({
    required this.child,
    required this.meta,
    required this.noBubble,
  });

  @override
  Widget build(BuildContext context) {
    final meta = SelectionContainer.disabled(child: this.meta);
    if (noBubble) {
      return Stack(
        children: [
          child,
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(100),
                borderRadius: BorderRadius.circular(10),
              ),
              child: meta,
            ),
          ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        child,
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 10, bottom: 5),
          child: meta,
        ),
      ],
    );
  }
}

class _MessageMeta extends StatelessWidget {
  final Event event;
  final bool ownMessage;
  final bool isEdited;
  final bool selected;
  final Color color;

  const _MessageMeta({
    required this.event,
    required this.ownMessage,
    required this.isEdited,
    required this.selected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: color);
    final status = event.status;
    // A single rich text instead of a Row, so that the detailed time of a
    // selected message wraps in narrow bubbles instead of overflowing.
    return Text.rich(
      TextSpan(
        children: [
          if (isEdited) TextSpan(text: '${L10n.of(context).edited} '),
          TextSpan(
            text: selected
                ? event.originServerTs.localizedDetailedTime(context)
                : event.originServerTs.localizedTimeOfDay(context),
          ),
          if (ownMessage)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(
                  status.isError
                      ? Icons.error_outline
                      : status.isSending
                      ? Icons.schedule
                      : event.isReadByOthers
                      ? Icons.done_all
                      : Icons.done,
                  size: 16,
                  color: status.isError
                      ? Theme.of(context).colorScheme.error
                      : color,
                ),
              ),
            ),
        ],
      ),
      style: style,
      textAlign: TextAlign.end,
    );
  }
}

class _AnimateIn extends StatefulWidget {
  final bool animateIn;
  final Widget child;
  const _AnimateIn({required this.animateIn, required this.child, super.key});

  @override
  State<_AnimateIn> createState() => __AnimateInState();
}

class __AnimateInState extends State<_AnimateIn> {
  bool _animationFinished = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.animateIn) return widget.child;
    if (!_animationFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _animationFinished = true;
        });
      });
    }

    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: _animationFinished ? widget.child : const SizedBox.shrink(),
    );
  }
}
