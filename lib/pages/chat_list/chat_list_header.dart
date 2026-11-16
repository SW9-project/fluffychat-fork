// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';

class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final cupertino = theme.cupertinoStyle;

    return SliverAppBar(
      // On iOS the large title above it is the primary bar.
      primary: !cupertino,
      floating: true,
      toolbarHeight: cupertino ? 52 : 72,
      pinned: isColumnMode,
      scrolledUnderElevation: 0,
      shape: isColumnMode
          ? Border(bottom: BorderSide(color: theme.dividerColor, width: 1))
          : null,
      backgroundColor: isColumnMode
          ? theme.colorScheme.surface.withAlpha(240)
          : Colors.transparent,
      automaticallyImplyLeading: false,
      title: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, snapshot) {
          final status =
              client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final hide =
              client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;
          return TextField(
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: (text) =>
                controller.onSearchEnter(text, globalSearch: globalSearch),
            style: cupertino ? const TextStyle(fontSize: 17) : null,
            decoration: InputDecoration(
              filled: true,
              // The search field of iOS, the search bar of Material 3.
              fillColor: cupertino
                  ? theme.colorScheme.surfaceContainer
                  : theme.colorScheme.surfaceContainerHigh,
              isDense: cupertino,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(cupertino ? 12 : 99),
              ),
              hintText: hide
                  ? L10n.of(context).searchChatsRooms
                  : status.calcLocalizedString(context),
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),

              prefixIcon: hide
                  ? controller.isSearchMode
                        ? IconButton(
                            tooltip: L10n.of(context).cancel,
                            icon: const Icon(Icons.close_outlined),
                            onPressed: controller.cancelSearch,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : isColumnMode ||
                              (controller.spaces.isEmpty &&
                                  !AppSettings.displayNavigationRail.value)
                        ? AccessibilityIconButtons(
                            button: AccessibleButton.search,
                            child: IconButton(
                              tooltip: L10n.of(context).search,
                              onPressed: controller.startSearch,
                              icon: Icon(
                                Icons.search_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : AccessibilityIconButtons(
                            button: AccessibleButton.menu,
                            child: IconButton(
                              tooltip: L10n.of(context).displayNavigationRail,
                              onPressed: controller.openNavrail,
                              icon: Icon(
                                Icons.menu,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                  : SizedBox(
                      width: 8,
                      height: 8,
                      child: Center(
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          value: status.progress,
                        ),
                      ),
                    ),
              suffixIcon: controller.isSearchMode && globalSearch
                  ? controller.isSearching
                        ? const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 10.0,
                              horizontal: 12,
                            ),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: controller.setServer,
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(99),
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(
                              controller.searchServer ??
                                  Matrix.of(context).client.homeserver!.host,
                              maxLines: 2,
                            ),
                          )
                  : SizedBox(width: 0, child: ClientChooserButton(controller)),
            ),
          );
        },
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

/// The large title of iOS above the search field. While scrolling it
/// collapses into a small title, like in Messages.
class ChatListLargeTitle extends StatelessWidget {
  const ChatListLargeTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CupertinoSliverNavigationBar(
      largeTitle: Text(L10n.of(context).chats),
      automaticallyImplyLeading: false,
      transitionBetweenRoutes: false,
      border: null,
      // Blurs the chats scrolled under it.
      backgroundColor: theme.colorScheme.surface.withAlpha(240),
      // In columns the navigation rail has the button to start a chat.
      trailing: FluffyThemes.isColumnMode(context)
          ? null
          : AccessibilityIconButtons(
              child: IconButton(
                tooltip: L10n.of(context).newChat,
                color: theme.colorScheme.primary,
                icon: const Icon(CupertinoIcons.square_pencil),
                onPressed: () => context.go('/rooms/newprivatechat'),
              ),
            ),
    );
  }
}
