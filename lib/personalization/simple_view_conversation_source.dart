// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:fluffychat/widgets/layouts/two_column_layout.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show Membership;
import 'package:provider/provider.dart';

import 'accessibility_scope.dart';
import 'quick_access_conversations.dart';
import 'simple_view_conversations.dart';
import 'simple_view_preview_scene.dart';
import 'simplified_interface.dart';

/// Resolves the active account at use time, without loading message history.
class SimpleViewConversationSource extends StatelessWidget {
  final Widget child;
  const SimpleViewConversationSource({super.key, required this.child});

  SimpleViewConversations _read(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final hidden = AppSettings.hideRoomsInSpaces.value
        ? client.rooms
              .where((r) => r.isSpace)
              .expand((r) => r.spaceChildren.map((child) => child.roomId))
              .toSet()
        : <String?>{};
    return SimpleViewConversations(
      '${client.homeserver}|${client.userID}',
      [
        for (final room in client.rooms)
          if (!room.isSpace &&
              room.membership == Membership.join &&
              !hidden.contains(room.id))
            QuickAccessConversation(
              id: room.id,
              name: room.getLocalizedDisplayname(),
              onOpen: () {},
            ),
      ],
      createPreview: (requestContext) {
        final home = requestContext
            .findAncestorStateOfType<ChatListController>();
        final snapshot = home == null ? null : ChatListPreviewState(home);
        return SimpleViewPreviewScene(
          mediaQuery: MediaQuery.of(context),
          theme: Theme.of(context),
          controller: SimplifiedInterfaceScope.maybeOf(context)!,
          accessibility: AccessibilityScope.maybeControllerOf(context),
          account: '${client.homeserver}|${client.userID}',
          screen: (_) => Provider<MatrixState>.value(
            value: matrix,
            child: Builder(
              builder: (previewContext) {
                final homeView = ChatList.preview(previewState: snapshot);
                final bar = MainNavigationBar(
                  activeTab: MainNavigationTab.chats,
                  unreadChats: client.rooms
                      .where(
                        (r) => r.isUnread || r.membership == Membership.invite,
                      )
                      .length,
                  onTabSelected: (_) {},
                );
                if (FluffyThemes.isColumnMode(previewContext)) {
                  return TwoColumnLayout(
                    mainView: homeView,
                    sideView: const EmptyPage(),
                    bottomBar: bar,
                  );
                }
                return Stack(
                  children: [
                    Positioned.fill(child: homeView),
                    Positioned(left: 0, right: 0, bottom: 0, child: bar),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) =>
      SimpleViewConversationsScope(resolve: () => _read(context), child: child);
}
