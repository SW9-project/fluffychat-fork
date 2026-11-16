// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/dummy_chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pages/chat_list/space_view.dart';
import 'package:fluffychat/personalization/quick_access_conversations.dart';
import 'package:fluffychat/personalization/simplified_interface.dart';
import 'package:fluffychat/personalization/simplified_interface_l10n.dart';
import 'package:fluffychat/personalization/simplified_interface_widgets.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';
import '../../widgets/matrix.dart';
import 'chat_list_header.dart';

class ChatListViewBody extends StatelessWidget {
  final ChatListController controller;

  const ChatListViewBody(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final simpleController = SimplifiedInterfaceScope.maybeOf(context);
    final simple = simpleController?.enabled ?? false;
    final simpleL10n = SimplifiedInterfaceL10n.of(context);

    final client = Matrix.of(context).client;
    final activeSpace = controller.activeSpaceId;
    if (activeSpace != null) {
      return SpaceView(
        key: ValueKey(activeSpace),
        spaceId: activeSpace,
        onBack: controller.clearActiveSpace,
        onChatTab: controller.onChatTap,
        activeChat: controller.activeChat,
      );
    }
    final spaces = client.rooms.where((r) => r.isSpace);
    final spaceDelegateCandidates = <String, Room>{};
    for (final space in spaces) {
      for (final spaceChild in space.spaceChildren) {
        final roomId = spaceChild.roomId;
        if (roomId == null) continue;
        spaceDelegateCandidates[roomId] = space;
      }
    }

    final publicRooms = controller.roomSearchResult?.chunk
        .where((room) => room.roomType != 'm.space')
        .toList();
    final publicSpaces = controller.roomSearchResult?.chunk
        .where((room) => room.roomType == 'm.space')
        .toList();
    final userSearchResult = controller.userSearchResult;
    const dummyChatCount = 4;
    final filter = controller.searchController.text.toLowerCase();
    return StreamBuilder(
      key: ValueKey(client.userID.toString()),
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final rooms = controller.filteredRooms
            .where(
              (room) =>
                  !AppSettings.hideRoomsInSpaces.value ||
                  spaceDelegateCandidates[room.id] == null,
            )
            .toList();

        final account = '${client.homeserver}|${client.userID}';
        final showQuick =
            simple &&
            !controller.isSearchMode &&
            simpleController!.preferences.quickAccess != SimpleQuickAccess.none;

        final quickRooms = client.rooms
            .where(
              (room) =>
                  !room.isSpace &&
                  room.membership == Membership.join &&
                  (!AppSettings.hideRoomsInSpaces.value ||
                      spaceDelegateCandidates[room.id] == null),
            )
            .toList();
        final automatic =
            simpleController?.preferences.quickAccess ==
            SimpleQuickAccess.frequent;
        final selected = automatic
            ? simpleController!.frequentFor(
                account,
                quickRooms.map((r) => r.id).toList(),
              )
            : simpleController?.quickAccessFor(account) ?? <String>[];
        final visibleQuickIds = showQuick
            ? selected.where((id) => quickRooms.any((r) => r.id == id)).toSet()
            : <String>{};
        final listRooms = rooms
            .where((r) => !visibleQuickIds.contains(r.id))
            .toList();
        return CustomScrollView(
          controller: controller.scrollController,
          slivers: [
            ChatListHeader(controller: controller),
            const SliverToBoxAdapter(child: SimplifiedInterfaceSwitch()),
            if (showQuick)
              SliverToBoxAdapter(
                child: QuickAccessConversations(
                  conversations: [
                    for (final room in quickRooms)
                      QuickAccessConversation(
                        id: room.id,
                        name: room.getLocalizedDisplayname(),
                        unread: room.notificationCount,
                        avatar: Avatar(
                          mxContent: room.avatar,
                          name: room.getLocalizedDisplayname(),
                          size: 40,
                        ),
                        onOpen: () => controller.onChatTap(room),
                      ),
                  ],
                  selectedIds: selected,
                  automatic: automatic,
                  onSave: (ids) async {
                    await simpleController.setQuickAccess(account, ids);
                    if (automatic) {
                      await simpleController.applyPreferences(
                        simpleController.preferences.copyWith(
                          quickAccess: SimpleQuickAccess.chosen,
                        ),
                        enabled: simpleController.enabled,
                        skipPreview: simpleController.skipPreview,
                      );
                    }
                  },
                ),
              ),
            if (simple && !controller.isSearchMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    visibleQuickIds.isNotEmpty
                        ? simpleL10n.others
                        : simpleL10n.conversations,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            SliverList(
              delegate: SliverChildListDelegate([
                if (controller.isSearchMode) ...[
                  SearchTitle(
                    title: L10n.of(context).publicRooms,
                    icon: const Icon(Icons.explore_outlined),
                  ),
                  PublicRoomsHorizontalList(publicRooms: publicRooms),
                  SearchTitle(
                    title: L10n.of(context).publicSpaces,
                    icon: const Icon(Icons.workspaces_outlined),
                  ),
                  PublicRoomsHorizontalList(publicRooms: publicSpaces),
                  SearchTitle(
                    title: L10n.of(context).users,
                    icon: const Icon(Icons.group_outlined),
                  ),
                  AnimatedContainer(
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    height:
                        userSearchResult == null ||
                            userSearchResult.results.isEmpty
                        ? 0
                        : 106,
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    child: userSearchResult == null
                        ? null
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: userSearchResult.results.length,
                            itemBuilder: (context, i) => _SearchItem(
                              title:
                                  userSearchResult.results[i].displayName ??
                                  userSearchResult
                                      .results[i]
                                      .userId
                                      .localpart ??
                                  L10n.of(context).unknownDevice,
                              avatar: userSearchResult.results[i].avatarUrl,
                              onPressed: () => UserDialog.show(
                                context: context,
                                profile: userSearchResult.results[i],
                              ),
                            ),
                          ),
                  ),
                ],
                if (client.rooms.isNotEmpty && !controller.isSearchMode)
                  if (simple)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PopupMenuButton<String>(
                        tooltip: simpleL10n.filter,
                        onSelected: (value) {
                          if (value.startsWith('tag:')) {
                            controller.setActiveFilter(
                              ActiveFilter.tag,
                              value.substring(4),
                            );
                          } else {
                            controller.setActiveFilter(
                              ActiveFilter.values.byName(value),
                              null,
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          for (final filter in ActiveFilter.values.where(
                            (f) => f != ActiveFilter.tag,
                          ))
                            CheckedPopupMenuItem(
                              value: filter.name,
                              checked: controller.activeFilter == filter,
                              child: Text(filter.toLocalizedString(context)),
                            ),
                          for (final tag in controller.roomTags.keys)
                            CheckedPopupMenuItem(
                              value: 'tag:$tag',
                              checked: controller.activeTag == tag,
                              child: Text(tag.replaceFirst('u.', '')),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Icon(Icons.filter_list),
                              Text(
                                '${simpleL10n.filter}: ${controller.activeFilter == ActiveFilter.tag ? (controller.activeTag ?? '').replaceFirst('u.', '') : controller.activeFilter.toLocalizedString(context)}',
                              ),
                              const Icon(Icons.expand_more),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: theme.dividerColor,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        children: [
                          ...ActiveFilter.values
                              .where((filter) => filter != ActiveFilter.tag)
                              .map(
                                (filter) => _FolderTab(
                                  selected: filter == controller.activeFilter,
                                  onTap: () =>
                                      controller.setActiveFilter(filter, null),
                                  label: filter.toLocalizedString(context),
                                ),
                              ),
                          ...controller.roomTags.entries.map(
                            (entry) => _FolderTab(
                              selected: entry.key == controller.activeTag,
                              onTap: () => controller.setActiveFilter(
                                ActiveFilter.tag,
                                entry.key,
                              ),
                              label: entry.key.replaceFirst('u.', ''),
                            ),
                          ),
                        ],
                      ),
                    ),
                if (controller.isSearchMode)
                  SearchTitle(
                    title: L10n.of(context).chats,
                    icon: const Icon(Icons.forum_outlined),
                  ),
                if (client.prevBatch != null &&
                    rooms.isEmpty &&
                    !controller.isSearchMode) ...[
                  Column(
                    mainAxisAlignment: .center,
                    children: [
                      if (!simple)
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            const Column(
                              mainAxisSize: .min,
                              children: [
                                DummyChatListItem(opacity: 0.5, animate: false),
                                DummyChatListItem(opacity: 0.3, animate: false),
                              ],
                            ),
                            Icon(
                              CupertinoIcons.chat_bubble_text_fill,
                              size: 128,
                              color: theme.colorScheme.secondary,
                            ),
                          ],
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          client.rooms.isEmpty
                              ? L10n.of(context).noChatsFoundHere
                              : L10n.of(context).noMoreChatsFound,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ]),
            ),
            if (client.prevBatch == null)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => DummyChatListItem(
                    opacity: (dummyChatCount - i) / dummyChatCount,
                    animate: true,
                  ),
                  childCount: dummyChatCount,
                ),
              ),
            if (client.prevBatch != null)
              SliverSafeArea(
                top: false,
                sliver: SliverList.builder(
                  itemCount: listRooms.length,
                  itemBuilder: (BuildContext context, int i) {
                    final room = listRooms[i];
                    final space = spaceDelegateCandidates[room.id];
                    if (simple &&
                        simpleController!.preferences.cleanHome &&
                        room.membership == Membership.join &&
                        !room.isSpace) {
                      return SimpleConversationTile(
                        conversation: QuickAccessConversation(
                          id: room.id,
                          name: room.getLocalizedDisplayname(),
                          unread: room.notificationCount,
                          avatar: Avatar(
                            mxContent: room.avatar,
                            name: room.getLocalizedDisplayname(),
                            size: 48,
                          ),
                          onOpen: () => controller.onChatTap(room),
                        ),
                      );
                    }
                    return ChatListItem(
                      room,
                      space: space,
                      key: Key('chat_list_item_${room.id}'),
                      filter: filter,
                      onTap: () => controller.onChatTap(room),
                      onLongPress: (context) =>
                          controller.chatContextAction(room, context, space),
                      activeChat: controller.activeChat == room.id,
                    );
                  },
                ),
              ),
            if (simple) const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        );
      },
    );
  }
}

class PublicRoomsHorizontalList extends StatelessWidget {
  const PublicRoomsHorizontalList({super.key, required this.publicRooms});

  final List<PublishedRoomsChunk>? publicRooms;

  @override
  Widget build(BuildContext context) {
    final publicRooms = this.publicRooms;
    return AnimatedContainer(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: publicRooms == null || publicRooms.isEmpty ? 0 : 106,
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: publicRooms == null
          ? null
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: publicRooms.length,
              itemBuilder: (context, i) => _SearchItem(
                title:
                    publicRooms[i].name ??
                    publicRooms[i].canonicalAlias?.localpart ??
                    L10n.of(context).group,
                avatar: publicRooms[i].avatarUrl,
                onPressed: () => showAdaptiveDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (c) => PublicRoomDialog(
                    roomAlias:
                        publicRooms[i].canonicalAlias ?? publicRooms[i].roomId,
                    chunk: publicRooms[i],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SearchItem extends StatelessWidget {
  final String title;
  final Uri? avatar;
  final void Function() onPressed;

  const _SearchItem({
    required this.title,
    this.avatar,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    child: SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: .min,
        children: [
          const SizedBox(height: 8),
          Avatar(mxContent: avatar, name: title),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Folder tab in the style of Telegram: Just a label with an indicator
/// line below when selected.
class _FolderTab extends StatelessWidget {
  final String label;
  final bool selected;
  final void Function() onTap;

  const _FolderTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: IntrinsicWidth(
          child: Column(
            mainAxisAlignment: .end,
            crossAxisAlignment: .stretch,
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                height: 3,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
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
