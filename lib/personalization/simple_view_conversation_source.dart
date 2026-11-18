// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' show Client, Membership, Room;

import 'quick_access_conversations.dart';
import 'simple_view_conversations.dart';

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

/// Resolves the active account at use time, without loading message history.
class SimpleViewConversationSource extends StatelessWidget {
  final Widget child;
  const SimpleViewConversationSource({super.key, required this.child});

  SimpleViewConversations _read(BuildContext context) {
    final client = Matrix.of(context).client;
    return SimpleViewConversations(simpleViewAccount(client), [
      for (final room in simpleViewRooms(client))
        QuickAccessConversation(
          id: room.id,
          name: room.getLocalizedDisplayname(),
          onOpen: () {},
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) =>
      SimpleViewConversationsScope(resolve: () => _read(context), child: child);
}
