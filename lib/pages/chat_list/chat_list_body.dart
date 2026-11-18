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
import 'package:fluffychat/pages/chat_list/glass_filter_bar.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pages/chat_list/space_view.dart';
import 'package:fluffychat/pages/chat_list/swipe_actions.dart';
import 'package:fluffychat/personalization/quick_access_conversations.dart';
import 'package:fluffychat/personalization/simple_view_conversation_source.dart';
import 'package:fluffychat/personalization/simplified_interface.dart';
import 'package:fluffychat/personalization/simplified_interface_l10n.dart';
import 'package:fluffychat/personalization/simplified_interface_widgets.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:go_router/go_router.dart';
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
        // A filter (unread, groups…) is empty although the account has chats.
        final filterEmpty =
            client.rooms.isNotEmpty &&
            controller.activeFilter != ActiveFilter.allChats;
        final rooms = controller.filteredRooms
            .where(
              (room) =>
                  !AppSettings.hideRoomsInSpaces.value ||
                  spaceDelegateCandidates[room.id] == null,
            )
            .toList();

        final account = simpleViewAccount(client);
        final showQuick =
            simple &&
            !controller.isSearchMode &&
            simpleController!.preferences.quickAccess != SimpleQuickAccess.none;
        final quickRooms = showQuick
            ? simpleViewRooms(client).toList()
            : const <Room>[];
        final automatic =
            simpleController?.preferences.quickAccess ==
            SimpleQuickAccess.frequent;
        final selected = !showQuick
            ? const <String>[]
            : automatic
            ? simpleController.frequentFor(
                account,
                quickRooms.map((r) => r.id).toList(),
              )
            : simpleController.quickAccessFor(account);
        final visibleQuickIds = selected
            .where((id) => quickRooms.any((r) => r.id == id))
            .toSet();
        final listRooms = rooms
            .where((r) => !visibleQuickIds.contains(r.id))
            .toList();
        return CustomScrollView(
          controller: controller.scrollController,
          slivers: [
            if (theme.cupertinoStyle) ChatListLargeTitle(controller),
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
                    // On iOS the search field has no room for the server.
                    trailing: theme.cupertinoStyle
                        ? CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            onPressed: controller.setServer,
                            child: Text(
                              controller.searchServer ??
                                  client.homeserver!.host,
                              style: const TextStyle(fontSize: 12),
                            ),
                          )
                        : null,
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
                  SizedBox(
                    height: 48,
                    child: PlatformInfos.supportsLiquidGlass
                        ? _NativeFolderTabs(controller)
                        : ListView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                            ),
                            shrinkWrap: true,
                            scrollDirection: Axis.horizontal,
                            children: [
                              ...ActiveFilter.values
                                  .where((filter) => filter != ActiveFilter.tag)
                                  .map(
                                    (filter) => _FolderTab(
                                      selected:
                                          filter == controller.activeFilter,
                                      onTap: () => controller.setActiveFilter(
                                        filter,
                                        null,
                                      ),
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
                      if (!simple && !filterEmpty)
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
                      if (filterEmpty)
                        _FilterEmptyState(controller)
                      else
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
                    // On mobile the actions of the long press menu are swipe
                    // actions.
                    final swipe = {
                      TargetPlatform.iOS,
                      TargetPlatform.android,
                    }.contains(theme.platform);
                    final item = ChatListItem(
                      room,
                      space: space,
                      key: Key('chat_list_item_${room.id}'),
                      filter: filter,
                      onTap: () => controller.onChatTap(room),
                      onLongPress: swipe
                          ? null
                          : (context) => controller.chatContextAction(
                              room,
                              context,
                              space,
                            ),
                      activeChat: controller.activeChat == room.id,
                    );
                    if (!swipe) return item;
                    return _ChatSwipeActions(
                      key: ValueKey(room.id),
                      controller: controller,
                      room: room,
                      space: space,
                      child: item,
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

/// The swipe actions of a chat on mobile, like in Messages and Mail.
class _ChatSwipeActions extends StatelessWidget {
  final ChatListController controller;
  final Room room;
  final Room? space;
  final Widget child;

  const _ChatSwipeActions({
    required this.controller,
    required this.room,
    required this.space,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    void run(ChatContextAction action) =>
        controller.runChatContextAction(room, action, space);
    final joined = room.membership == Membership.join;
    final invited = room.membership == Membership.invite;
    final muted = room.pushRuleState != PushRuleState.notify;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return SwipeActions(
      leading: [
        if (joined) ...[
          SwipeAction(
            label: room.markedUnread ? l10n.markAsRead : l10n.unread,
            icon: room.markedUnread
                ? (ios ? CupertinoIcons.chat_bubble_fill : Icons.mark_chat_read)
                : (ios
                      ? CupertinoIcons.chat_bubble_text_fill
                      : Icons.mark_chat_unread),
            color: ios ? CupertinoColors.systemBlue : Colors.blue,
            onPressed: () => run(ChatContextAction.markUnread),
          ),
          SwipeAction(
            label: room.isFavourite ? l10n.unpin : l10n.pin,
            icon: room.isFavourite
                ? (ios
                      ? CupertinoIcons.pin_slash_fill
                      : Icons.push_pin_outlined)
                : (ios ? CupertinoIcons.pin_fill : Icons.push_pin),
            color: ios ? CupertinoColors.systemOrange : Colors.orange,
            onPressed: () => run(ChatContextAction.favorite),
          ),
        ],
      ],
      trailing: [
        if (joined) ...[
          SwipeAction(
            label: l10n.more,
            icon: ios ? CupertinoIcons.ellipsis_circle_fill : Icons.more_horiz,
            color: ios ? CupertinoColors.systemGrey : Colors.grey,
            onPressed: () => run(ChatContextAction.showMore),
          ),
          SwipeAction(
            label: muted ? l10n.unmuteChat : l10n.muteChat,
            icon: muted
                ? (ios ? CupertinoIcons.bell_fill : Icons.notifications)
                : (ios
                      ? CupertinoIcons.bell_slash_fill
                      : Icons.notifications_off),
            color: ios ? CupertinoColors.systemIndigo : Colors.indigo,
            onPressed: () => run(ChatContextAction.mute),
          ),
        ],
        if (invited)
          SwipeAction(
            label: l10n.block,
            icon: ios ? CupertinoIcons.hand_raised_fill : Icons.block,
            color: ios ? CupertinoColors.systemGrey : Colors.grey,
            onPressed: () => run(ChatContextAction.block),
          ),
        SwipeAction(
          label: invited ? l10n.delete : l10n.leave,
          icon: ios ? CupertinoIcons.trash_fill : Icons.delete,
          color: ios ? CupertinoColors.systemRed : Colors.red,
          onPressed: () => run(ChatContextAction.leave),
        ),
      ],
      child: child,
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
/// The same filters as the [_FolderTab]s, drawn by UIKit since iOS 26.
class _NativeFolderTabs extends StatelessWidget {
  final ChatListController controller;

  const _NativeFolderTabs(this.controller);

  @override
  Widget build(BuildContext context) {
    final filters = ActiveFilter.values
        .where((filter) => filter != ActiveFilter.tag)
        .toList();
    final tags = controller.roomTags.keys.toList();
    final tagIndex = tags.indexOf(controller.activeTag ?? '');
    final selectedIndex = controller.activeFilter != ActiveFilter.tag
        ? filters.indexOf(controller.activeFilter)
        : tagIndex < 0
        ? null
        : filters.length + tagIndex;
    return GlassFilterBar(
      labels: [
        for (final filter in filters) filter.toLocalizedString(context),
        for (final tag in tags) tag.replaceFirst('u.', ''),
      ],
      selectedIndex: selectedIndex,
      onSelected: (index) => index < filters.length
          ? controller.setActiveFilter(filters[index], null)
          : controller.setActiveFilter(
              ActiveFilter.tag,
              tags[index - filters.length],
            ),
    );
  }
}

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
    // Filled when selected: the accent on iOS, the secondary container of
    // Material 3 filter chips on Android.
    final selectedColor = theme.cupertinoStyle
        ? theme.colorScheme.primary
        : theme.colorScheme.secondaryContainer;
    final onSelectedColor = theme.cupertinoStyle
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSecondaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 6.0),
      child: Material(
        color: selected ? selectedColor : theme.colorScheme.surfaceContainer,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? onSelectedColor
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the selected filter has no chats but the account has some.
class _FilterEmptyState extends StatelessWidget {
  final ChatListController controller;

  const _FilterEmptyState(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final (icon, title, body) = switch (controller.activeFilter) {
      ActiveFilter.unread => (
        Icons.mark_chat_read_outlined,
        l10n.emptyUnreadTitle,
        l10n.emptyUnreadBody,
      ),
      ActiveFilter.groups => (
        Icons.groups_outlined,
        l10n.emptyGroupsTitle,
        l10n.emptyGroupsBody,
      ),
      ActiveFilter.messages => (
        Icons.chat_bubble_outline,
        l10n.emptyDirectChatsTitle,
        l10n.emptyDirectChatsBody,
      ),
      _ => (
        Icons.filter_list_off_outlined,
        l10n.emptyFilterTitle,
        l10n.emptyFilterBody,
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(
        mainAxisSize: .min,
        spacing: 12,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              icon,
              size: 40,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          if (controller.activeFilter == ActiveFilter.groups)
            FilledButton.tonalIcon(
              onPressed: () => context.go('/rooms/newgroup'),
              icon: const Icon(Icons.group_add_outlined),
              label: Text(l10n.createGroup),
            ),
          TextButton(
            onPressed: () =>
                controller.setActiveFilter(ActiveFilter.allChats, null),
            child: Text(l10n.showAllChats),
          ),
        ],
      ),
    );
  }
}
