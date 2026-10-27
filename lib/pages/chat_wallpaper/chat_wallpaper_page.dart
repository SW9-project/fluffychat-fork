// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_wallpaper/wallpaper_editor.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

/// Lets the user change the wallpaper of a single chat.
class ChatWallpaperPage extends StatelessWidget {
  final String roomId;

  const ChatWallpaperPage({required this.roomId, super.key});

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L10n.of(context).wallpaper),
          subtitle: Text(
            room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      body: MaxWidthBody(child: WallpaperEditor(room: room)),
    );
  }
}
