// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' show Membership;

import 'quick_access_conversations.dart';
import 'simple_view_conversations.dart';

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
    return SimpleViewConversations('${client.homeserver}|${client.userID}', [
      for (final room in client.rooms)
        if (!room.isSpace &&
            room.membership == Membership.join &&
            !hidden.contains(room.id))
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
