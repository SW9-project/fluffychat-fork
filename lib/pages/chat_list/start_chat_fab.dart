// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class StartChatFab extends StatelessWidget {
  /// With its label, like the Material 3 button below a list.
  final bool extended;

  const StartChatFab({this.extended = false, super.key});

  @override
  Widget build(BuildContext context) {
    void onPressed() => context.go('/rooms/newprivatechat');
    if (extended) {
      return FloatingActionButton.extended(
        heroTag: 'start_chat_fab',
        onPressed: onPressed,
        icon: const Icon(Icons.edit_outlined),
        label: Text(L10n.of(context).newChat),
      );
    }
    return FloatingActionButton(
      heroTag: 'start_chat_fab',
      tooltip: L10n.of(context).newChat,
      onPressed: onPressed,
      child: const Icon(Icons.edit_outlined),
    );
  }
}
