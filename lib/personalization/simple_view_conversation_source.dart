// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'accessibility_scope.dart';
import 'quick_access_conversations.dart';
import 'simple_view_conversations.dart';
import 'simple_view_preview_scene.dart';
import 'simplified_interface.dart';
import 'simplified_interface_l10n.dart';

/// The key shortcuts and open counts are stored under, per account.
String simpleViewAccount(Client client) =>
    '${client.homeserver}|${client.userID}';

/// The joined chats a shortcut can point to, as the chat list shows them.
Iterable<Room> simpleViewRooms(Client client) {
  final hidden = AppSettings.hideRoomsInSpaces.value
      ? client.rooms
            .where((r) => r.isSpace)
            .expand((r) => r.spaceChildren.map((child) => child.roomId))
            .toSet()
      : const <String?>{};
  return client.rooms.where(
    (room) =>
        !room.isSpace &&
        room.membership == Membership.join &&
        !hidden.contains(room.id),
  );
}

/// How many conversations the preview list shows, besides any fixed chats.
int simpleViewPreviewCount({required bool simple}) => simple ? 2 : 5;

/// Detached example chats that fill the preview when an account has too few.
/// They are never added to the client, so nothing is sent or stored.
List<Room> simpleViewExampleRooms(Client client, SimplifiedInterfaceL10n text) {
  final now = DateTime.now();
  return [
    for (final (i, (name, body)) in [
      ('Ana', text.sampleHello),
      ('Luis', text.sampleBye),
      ('Marta', text.sampleHowAreYou),
      ('Pablo', text.sampleThanks),
      ('Sofía', text.sampleTomorrow),
    ].indexed)
      () {
        final sender = '@example${i + 1}:example.org';
        final room = Room(
          id: '!simple-view-example-${i + 1}:example.org',
          client: client,
          notificationCount: i == 0 ? 1 : 0,
        );
        room
          ..setState(
            StrippedStateEvent(
              type: EventTypes.RoomName,
              content: {'name': name},
              senderId: sender,
              stateKey: '',
            ),
          )
          // A known sender keeps the list from fetching a profile.
          ..setState(
            StrippedStateEvent(
              type: EventTypes.RoomMember,
              content: {'membership': 'join', 'displayname': name},
              senderId: sender,
              stateKey: sender,
            ),
          )
          ..lastEvent = Event(
            content: {'msgtype': MessageTypes.Text, 'body': body},
            type: EventTypes.Message,
            eventId: '\$simple-view-example-${i + 1}',
            senderId: sender,
            originServerTs: now.subtract(Duration(minutes: 5 + 55 * i)),
            room: room,
          );
        return room;
      }(),
  ];
}

/// Resolves the active account at use time, without loading message history.
class SimpleViewConversationSource extends StatelessWidget {
  final Widget child;
  const SimpleViewConversationSource({super.key, required this.child});

  SimpleViewConversations _read(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = matrix.client;
    return SimpleViewConversations(
      simpleViewAccount(client),
      [
        for (final room in simpleViewRooms(client))
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
        final media = MediaQuery.of(context);
        // Wide windows show the chats in one column of this width.
        final width = FluffyThemes.isColumnMode(context)
            ? FluffyThemes.columnWidth
            : media.size.width;
        return SimpleViewPreviewScene(
          // Only the chats: no status bar, keyboard, or navigation bar space.
          mediaQuery: media
              .removePadding(
                removeTop: true,
                removeBottom: true,
                removeLeft: true,
                removeRight: true,
              )
              .removeViewInsets(removeBottom: true)
              .copyWith(size: Size(width, media.size.height)),
          theme: Theme.of(context),
          controller: SimplifiedInterfaceScope.maybeOf(context)!,
          accessibility: AccessibilityScope.maybeControllerOf(context),
          account: simpleViewAccount(client),
          screen: (_) => Provider<MatrixState>.value(
            value: matrix,
            child: ChatList.preview(previewState: snapshot),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) =>
      SimpleViewConversationsScope(resolve: () => _read(context), child: child);
}
