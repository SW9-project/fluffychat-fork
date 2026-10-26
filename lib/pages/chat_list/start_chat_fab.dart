// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class StartChatFab extends StatelessWidget {
  const StartChatFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'start_chat_fab',
      tooltip: L10n.of(context).newChat,
      onPressed: () => context.go('/rooms/newprivatechat'),
      child: const Icon(Icons.edit),
    );
  }
}
