// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:url_launcher/url_launcher_string.dart';

import 'chat_list.dart';

class ClientChooserButton extends StatelessWidget {
  final ChatListController controller;

  const ClientChooserButton(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = Result(() => matrix.client).asValue?.value;

    var clientCount = 0;
    matrix.accountBundles.forEach((key, value) => clientCount += value.length);
    return FutureBuilder<Profile>(
      future: client?.isLogged() == true ? client?.fetchOwnProfile() : null,
      builder: (context, snapshot) {
        final avatar = Avatar(
          mxContent: snapshot.data?.avatarUrl,
          name: snapshot.data?.displayName ?? client?.userID?.localpart,
          size: 32,
        );
        if (PlatformInfos.isIOS) return _nativeMenu(context, avatar);
        return Material(
          clipBehavior: Clip.hardEdge,
          borderRadius: BorderRadius.circular(99),
          color: Colors.transparent,
          child: PopupMenuButton<SettingsAction>(
            key: Key('accounts_and_settings_buttons'),
            tooltip: L10n.of(context).accountsAndSettings,
            // Above the floating bar, which hides for menus in the shell.
            useRootNavigator: true,
            onSelected: (action) => _clientSelected(action, context),
            itemBuilder: (context) {
              final titles = _titles(L10n.of(context));
              return [
                for (final (i, action) in _menu.keys.indexed)
                  PopupMenuItem(
                    value: action,
                    child: Row(
                      children: [
                        Icon(_menu[action]!.$2),
                        const SizedBox(width: 18),
                        Flexible(child: Text(titles[i])),
                      ],
                    ),
                  ),
              ];
            },
            icon: avatar,
          ),
        );
      },
    );
  }

  /// The same actions on every platform, with their SF Symbol and Material
  /// icon.
  static const _menu = {
    SettingsAction.archive: ('archivebox', Icons.archive_outlined),
    SettingsAction.newGroup: ('person.2', Icons.group_add_outlined),
    SettingsAction.setStatus: ('pencil', Icons.edit_outlined),
    SettingsAction.support: ('heart', Icons.favorite_border),
  };

  static List<String> _titles(L10n l10n) => [
    l10n.archive,
    l10n.createGroup,
    l10n.setStatus,
    l10n.supportFluffyChat,
  ];

  /// A native `UIMenu` over the avatar, see `NativeMenuButton.swift`.
  Widget _nativeMenu(BuildContext context, Widget avatar) {
    final l10n = L10n.of(context);
    final params = {
      'label': l10n.accountsAndSettings,
      'titles': _titles(l10n),
      'symbols': _menu.values.map((item) => item.$1).toList(),
      'isDark': Theme.of(context).brightness == Brightness.dark,
    };
    return SizedBox.square(
      dimension: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          avatar,
          Positioned.fill(
            child: UiKitView(
              // A new key recreates the view, which reads its parameters once.
              key: ValueKey(const DeepCollectionEquality().hash(params)),
              viewType: 'fluffychat/menu_button',
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
              gestureRecognizers: {Factory(EagerGestureRecognizer.new)},
              onPlatformViewCreated: (id) =>
                  MethodChannel(
                    'fluffychat/menu_button/$id',
                  ).setMethodCallHandler((call) async {
                    if (call.method != 'selected' || !context.mounted) {
                      return;
                    }
                    _clientSelected(
                      _menu.keys.elementAt(call.arguments as int),
                      context,
                    );
                  }),
            ),
          ),
        ],
      ),
    );
  }

  void _clientSelected(SettingsAction action, BuildContext context) {
    switch (action) {
      case SettingsAction.newGroup:
        context.go('/rooms/newgroup');
      case SettingsAction.support:
        launchUrlString(
          'https://ko-fi.com/post/How-can-I-support-FluffyChat-J2G325WE6I',
        );
      case SettingsAction.archive:
        context.go('/rooms/archive');
      case SettingsAction.setStatus:
        controller.setStatus();
    }
  }
}

enum SettingsAction { newGroup, setStatus, support, archive }
