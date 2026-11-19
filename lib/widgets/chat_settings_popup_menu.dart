// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/appearance_l10n.dart';
import 'package:fluffychat/personalization/simplified_interface.dart';
import 'package:fluffychat/personalization/simplified_interface_l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/native_menu_button.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'matrix.dart';

enum ChatPopupMenuActions { details, encryption, leave, search }

class ChatSettingsPopupMenu extends StatefulWidget {
  final Room room;
  final bool displayChatDetails;

  const ChatSettingsPopupMenu(this.room, this.displayChatDetails, {super.key});

  @override
  ChatSettingsPopupMenuState createState() => ChatSettingsPopupMenuState();
}

class ChatSettingsPopupMenuState extends State<ChatSettingsPopupMenu> {
  StreamSubscription? notificationChangeSub;

  @override
  void dispose() {
    notificationChangeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    notificationChangeSub ??= Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.accountData?.any(
                (accountData) => accountData.type == 'm.push_rules',
              ) ??
              false,
        )
        .listen((u) => setState(() {}));
    final l10n = L10n.of(context);
    final simplified = SimplifiedInterfaceScope.enabledOf(context);
    final tooltip = simplified
        ? SimplifiedInterfaceL10n.of(context).more
        : AppearanceL10n.of(context).labelMenu;
    // Each action with its Material icon and SF Symbol.
    final items = [
      if (widget.displayChatDetails && widget.room.membership == .join)
        (
          ChatPopupMenuActions.details,
          (Icons.info_outline_rounded, 'info.circle'),
          l10n.chatDetails,
        ),
      if (widget.room.membership case .join || .leave) ...[
        (
          ChatPopupMenuActions.search,
          (Icons.search_outlined, 'magnifyingglass'),
          l10n.search,
        ),
        (
          ChatPopupMenuActions.encryption,
          (Icons.lock_outlined, 'lock'),
          l10n.encryption,
        ),
      ],
      (
        ChatPopupMenuActions.leave,
        (Icons.delete_outlined, 'trash'),
        l10n.leave,
      ),
    ];
    // The simplified interface has its own labeled child.
    final simplifiedChild = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.more_vert),
          Text(
            SimplifiedInterfaceL10n.of(context).moreShort,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
    final icon = LabeledIcon(
      icon: Icon(Icons.adaptive.more),
      label: AppearanceL10n.of(context).labelMenu,
    );
    if (PlatformInfos.isIOS) {
      return NativeMenuButton(
        label: tooltip,
        titles: [for (final item in items) item.$3],
        symbols: [for (final item in items) item.$2.$2],
        destructive: [items.length - 1],
        onSelected: (i) => _onSelected(items[i].$1),
        // Only the look of the button: the native view on top takes taps.
        child: simplified
            ? simplifiedChild
            : IgnorePointer(
                child: IconButton(onPressed: () {}, icon: icon),
              ),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        const SizedBox.shrink(),
        PopupMenuButton<ChatPopupMenuActions>(
          useRootNavigator: true,
          tooltip: tooltip,
          icon: simplified ? null : icon,
          onSelected: _onSelected,
          itemBuilder: (context) => [
            for (final (action, (icon, _), title) in items)
              PopupMenuItem<ChatPopupMenuActions>(
                value: action,
                child: Row(
                  children: [
                    Icon(icon),
                    const SizedBox(width: 12),
                    Text(title),
                  ],
                ),
              ),
          ],
          child: simplified ? simplifiedChild : null,
        ),
      ],
    );
  }

  Future<void> _onSelected(ChatPopupMenuActions choice) async {
    switch (choice) {
      case ChatPopupMenuActions.leave:
        final l10n = L10n.of(context);
        final router = GoRouter.of(context);
        final confirmed = await showOkCancelAlertDialog(
          context: context,
          title: l10n.areYouSure,
          message: l10n.archiveRoomDescription,
          okLabel: l10n.leave,
          cancelLabel: l10n.cancel,
          isDestructive: true,
        );
        if (confirmed != OkCancelResult.ok) return;
        if (!mounted) return;
        final result = await showFutureLoadingDialog(
          context: context,
          future: () => widget.room.leave(),
        );
        if (result.error == null) {
          router.go('/rooms');
        }

        break;
      case ChatPopupMenuActions.details:
        _showChatDetails();
        break;
      case ChatPopupMenuActions.search:
        context.go('/rooms/${widget.room.id}/search');
        break;
      case ChatPopupMenuActions.encryption:
        context.go('/rooms/${widget.room.id}/encryption');
        break;
    }
  }

  void _showChatDetails() {
    if (GoRouterState.of(context).uri.path.endsWith('/details')) {
      context.go('/rooms/${widget.room.id}');
    } else {
      context.go('/rooms/${widget.room.id}/details');
    }
  }
}
