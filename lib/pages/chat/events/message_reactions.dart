// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart' show IterableExtension;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/sticker_picker_dialog.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MessageReactions extends StatelessWidget {
  final Event event;
  final Timeline timeline;

  const MessageReactions(this.event, this.timeline, {super.key});

  @override
  Widget build(BuildContext context) {
    final allReactionEvents = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final reactionMap = <String, _ReactionEntry>{};
    final client = Matrix.of(context).client;

    for (final e in allReactionEvents) {
      final key = e.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) {
        if (!reactionMap.containsKey(key)) {
          reactionMap[key] = _ReactionEntry(
            key: key,
            count: 0,
            reacted: false,
            reactors: [],
          );
        }
        reactionMap[key]!.count++;
        reactionMap[key]!.reactors!.add(e.senderFromMemoryOrFallback);
        reactionMap[key]!.reacted |= e.senderId == e.room.client.userID;
      }
    }

    final reactionList = reactionMap.values.toList();
    reactionList.sort((a, b) => b.count - a.count > 0 ? 1 : -1);
    final ownMessage = event.senderId == event.room.client.userID;
    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      alignment: ownMessage ? WrapAlignment.end : WrapAlignment.start,
      children: [
        ...reactionList.map(
          (r) => _Reaction(
            reactionKey: r.key,
            count: r.count,
            reacted: r.reacted,
            onTap: () {
              if (r.reacted) {
                final evt = allReactionEvents.firstWhereOrNull(
                  (e) =>
                      e.senderId == e.room.client.userID &&
                      e.content.tryGetMap('m.relates_to')?['key'] == r.key,
                );
                if (evt != null) {
                  showFutureLoadingDialog(
                    context: context,
                    future: evt.redactEvent,
                  );
                }
              } else {
                event.room.sendReaction(event.eventId, r.key);
              }
            },
            onLongPress: () async => await _AdaptableReactorsDialog(
              client: client,
              reactionEntry: r,
            ).show(context),
          ),
        ),
      ],
    );
  }
}

class _Reaction extends StatelessWidget {
  final String reactionKey;
  final int count;
  final bool? reacted;
  final void Function()? onTap;
  final void Function()? onLongPress;

  const _Reaction({
    required this.reactionKey,
    required this.count,
    required this.reacted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (reactionKey.startsWith('mxc://')) {
      content = MxcImage(
        uri: Uri.parse(reactionKey),
        width: 20,
        height: 20,
        animated: false,
        isThumbnail: false,
      );
    } else {
      var renderKey = Characters(reactionKey);
      if (renderKey.length > 10) {
        renderKey = renderKey.getRange(0, 9) + Characters('…');
      }
      content = Text(renderKey.toString(), style: TextStyle(fontSize: 14));
    }
    // iOS: a capsule with the count inside, tinted when the user reacted.
    if (theme.cupertinoStyle) {
      final tint = theme.colorScheme.primary;
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(minHeight: 26),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: ShapeDecoration(
            color: reacted == true
                ? tint.withAlpha(46)
                : theme.colorScheme.surfaceContainerHigh,
            shape: StadiumBorder(
              side: reacted == true
                  ? BorderSide(color: tint.withAlpha(140))
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: .min,
            children: [
              content,
              if (count > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: reacted == true
                          ? tint
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Badge(
      isLabelVisible: count > 1,
      label: Text(count.toString()),
      textStyle: TextStyle(fontSize: 10),
      textColor: theme.colorScheme.onPrimary,
      backgroundColor: theme.colorScheme.primary.withAlpha(200),
      child: InkWell(
        onTap: () => onTap != null ? onTap!() : null,
        onLongPress: () => onLongPress != null ? onLongPress!() : null,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            border: Border.all(
              color: reacted == true
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.secondaryContainer,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
          // A minimum height lets the chip grow with the text scale.
          constraints: const BoxConstraints(minHeight: 24),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: content,
        ),
      ),
    );
  }
}

class _ReactionEntry {
  String key;
  int count;
  bool reacted;
  List<User>? reactors;

  _ReactionEntry({
    required this.key,
    required this.count,
    required this.reacted,
    this.reactors,
  });
}

class _AdaptableReactorsDialog extends StatelessWidget {
  final Client? client;
  final _ReactionEntry? reactionEntry;

  const _AdaptableReactorsDialog({this.client, this.reactionEntry});

  Future<bool?> show(BuildContext context) => showDialog(
    context: context,
    builder: (context) => this,
    barrierDismissible: true,
    useRootNavigator: false,
  );

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final reactor in reactionEntry!.reactors!)
            Chip(
              avatar: Avatar(
                mxContent: reactor.avatarUrl,
                name: reactor.displayName,
                client: client,
                presenceUserId: reactor.stateKey,
              ),
              label: Text(reactor.displayName!),
            ),
        ],
      ),
    );

    final title = Center(child: Text(reactionEntry!.key));

    return AlertDialog(title: title, content: body);
  }
}

/// Lets the user pick any emoji or one of the room's emotes as reaction.
Future<String?> showCustomReactionPicker(BuildContext context, Room room) {
  final theme = Theme.of(context);
  final l10n = L10n.of(context);
  return showAdaptiveBottomSheet<String>(
    context: context,
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: Text(l10n.customReaction),
        leading: CloseButton(onPressed: () => Navigator.of(context).pop(null)),
      ),
      body: SizedBox(
        height: double.infinity,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              if (theme.cupertinoStyle)
                Builder(
                  builder: (context) {
                    final tabs = DefaultTabController.of(context);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: AnimatedBuilder(
                        animation: tabs,
                        builder: (context, _) =>
                            CupertinoSlidingSegmentedControl<int>(
                              groupValue: tabs.index,
                              onValueChanged: (i) => tabs.animateTo(i ?? 0),
                              children: {
                                0: Text(l10n.emojis),
                                1: Text(l10n.stickers),
                              },
                            ),
                      ),
                    );
                  },
                )
              else
                TabBar(
                  tabs: [
                    Tab(text: l10n.emojis),
                    Tab(text: l10n.stickers),
                  ],
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    EmojiPicker(
                      onEmojiSelected: (_, emoji) =>
                          Navigator.of(context).pop(emoji.emoji),
                      config: Config(
                        locale: Localizations.localeOf(context),
                        emojiViewConfig: const EmojiViewConfig(
                          backgroundColor: Colors.transparent,
                        ),
                        bottomActionBarConfig: const BottomActionBarConfig(
                          enabled: false,
                        ),
                        categoryViewConfig: CategoryViewConfig(
                          initCategory: Category.SMILEYS,
                          backspaceColor: theme.colorScheme.primary,
                          iconColor: theme.colorScheme.primary.withAlpha(128),
                          iconColorSelected: theme.colorScheme.primary,
                          indicatorColor: theme.colorScheme.primary,
                          backgroundColor: theme.colorScheme.surface,
                        ),
                        skinToneConfig: SkinToneConfig(
                          dialogBackgroundColor: Color.lerp(
                            theme.colorScheme.surface,
                            theme.colorScheme.primaryContainer,
                            0.75,
                          )!,
                          indicatorColor: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    StickerPickerDialog(
                      room: room,
                      usage: ImagePackUsage.emoticon,
                      onSelected: (sticker) =>
                          Navigator.of(context).pop(sticker.url.toString()),
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
}
