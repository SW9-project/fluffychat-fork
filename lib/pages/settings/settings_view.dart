// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/personalization_l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings_section.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../widgets/mxc_image_viewer.dart';
import 'settings.dart';

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    final background = SettingsSection.backgroundColor(theme);
    final chevron = settingsChevron(theme);
    return MainNavigationBarInsets(
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          title: Text(L10n.of(context).settings),
          automaticallyImplyLeading: false,
          backgroundColor: background,
        ),
        body: ListTileTheme(
          iconColor: theme.colorScheme.onSurface,
          child: ListView(
            key: const Key('SettingsListViewContent'),
            children: <Widget>[
              FutureBuilder<Profile>(
                future: controller.profileFuture,
                builder: (context, snapshot) {
                  final profile = snapshot.data;
                  final avatar = profile?.avatarUrl;
                  final mxid =
                      Matrix.of(context).client.userID ?? L10n.of(context).user;
                  final displayname =
                      profile?.displayName ?? mxid.localpart ?? mxid;
                  final avatarActions = [
                    if (PlatformInfos.isMobile) AvatarAction.camera,
                    AvatarAction.file,
                    if (avatar != null) AvatarAction.remove,
                  ];
                  final avatarButtonStyle = IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    shadowColor: theme.colorScheme.shadow,
                    elevation: 2,
                  );
                  return Column(
                    crossAxisAlignment: .center,
                    mainAxisSize: .min,
                    children: [
                      Stack(
                        children: [
                          Avatar(
                            mxContent: avatar,
                            name: displayname,
                            size: Avatar.defaultSize * 2.5,
                            animated: true,
                            onTap: avatar != null
                                ? () => showDialog(
                                    context: context,
                                    builder: (_) => MxcImageViewer(avatar),
                                  )
                                : null,
                          ),
                          if (profile != null)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: avatarActions.length == 1
                                  ? IconButton(
                                      style: avatarButtonStyle,
                                      tooltip: L10n.of(
                                        context,
                                      ).changeYourAvatar,
                                      onPressed: () =>
                                          controller.setAvatarAction(
                                            avatarActions.single,
                                          ),
                                      icon: const Icon(
                                        Icons.camera_alt_outlined,
                                      ),
                                    )
                                  : PopupMenuButton<AvatarAction>(
                                      style: avatarButtonStyle,
                                      tooltip: L10n.of(
                                        context,
                                      ).changeYourAvatar,
                                      onSelected: controller.setAvatarAction,
                                      icon: const Icon(
                                        Icons.camera_alt_outlined,
                                      ),
                                      itemBuilder: (context) => [
                                        for (final action in avatarActions)
                                          PopupMenuItem(
                                            value: action,
                                            child: Row(
                                              mainAxisSize: .min,
                                              spacing: 12,
                                              children: [
                                                Icon(switch (action) {
                                                  AvatarAction.camera =>
                                                    Icons.camera_alt_outlined,
                                                  AvatarAction.file =>
                                                    Icons.photo_outlined,
                                                  AvatarAction.remove =>
                                                    Icons.delete_outlined,
                                                }),
                                                Text(switch (action) {
                                                  AvatarAction.camera =>
                                                    L10n.of(context).openCamera,
                                                  AvatarAction.file => L10n.of(
                                                    context,
                                                  ).openGallery,
                                                  AvatarAction.remove =>
                                                    L10n.of(
                                                      context,
                                                    ).removeYourAvatar,
                                                }),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: controller.setDisplaynameAction,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurface,
                          iconColor: theme.colorScheme.onSurface,
                        ),
                        label: Text(
                          displayname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      TextButton(
                        onPressed: () => FluffyShare.share(mxid, context),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.secondary,
                          iconColor: theme.colorScheme.secondary,
                        ),
                        child: Text(
                          mxid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
              FutureBuilder(
                future: Result.capture(
                  Matrix.of(context).client.getAuthMetadata(),
                ).then((result) => result.asValue?.value),
                builder: (context, snapshot) {
                  final accountManageUrl = snapshot.data?.accountManagementUri;
                  return SettingsSection(
                    children: [
                      SwitchListTile.adaptive(
                        controlAffinity: ListTileControlAffinity.trailing,
                        value: controller.cryptoIdentityConnected == true,
                        secondary: const SettingsIcon(
                          Icons.backup_outlined,
                          CupertinoIcons.cloud_upload_fill,
                          CupertinoColors.systemBlue,
                        ),
                        title: Text(L10n.of(context).chatBackup),
                        onChanged: controller.firstRunBootstrapAction,
                        contentPadding: EdgeInsets.only(left: 16, right: 8),
                      ),
                      if (accountManageUrl != null)
                        ListTile(
                          leading: const SettingsIcon(
                            Icons.account_circle_outlined,
                            CupertinoIcons.person_crop_circle_fill,
                            CupertinoColors.systemGrey,
                          ),
                          title: Text(L10n.of(context).manageAccount),
                          trailing: const Icon(Icons.open_in_new_outlined),
                          onTap: () => launchUrl(
                            accountManageUrl,
                            mode: LaunchMode.inAppBrowserView,
                          ),
                        ),
                    ],
                  );
                },
              ),
              SettingsSection(
                children: [
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.format_paint_outlined,
                      CupertinoIcons.paintbrush_fill,
                      CupertinoColors.systemIndigo,
                    ),
                    trailing: chevron,
                    title: Text(L10n.of(context).changeTheme),
                    tileColor: activeRoute.startsWith('/rooms/settings/style')
                        ? theme.colorScheme.surfaceContainerHigh
                        : null,
                    onTap: () => context.go('/rooms/settings/style'),
                  ),
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.accessibility_new_outlined,
                      CupertinoIcons.person_fill,
                      CupertinoColors.systemBlue,
                    ),
                    trailing: chevron,
                    title: Text(PersonalizationL10n.of(context).accessibility),
                    tileColor:
                        activeRoute.startsWith('/rooms/settings/accessibility')
                        ? theme.colorScheme.surfaceContainerHigh
                        : null,
                    onTap: () => context.go('/rooms/settings/accessibility'),
                  ),
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.notifications_outlined,
                      CupertinoIcons.bell_fill,
                      CupertinoColors.systemRed,
                    ),
                    trailing: chevron,
                    title: Text(L10n.of(context).notifications),
                    tileColor:
                        activeRoute.startsWith('/rooms/settings/notifications')
                        ? theme.colorScheme.surfaceContainerHigh
                        : null,
                    onTap: () => context.go('/rooms/settings/notifications'),
                  ),
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.devices_outlined,
                      CupertinoIcons.device_phone_portrait,
                      CupertinoColors.systemGrey,
                    ),
                    trailing: chevron,
                    title: Text(L10n.of(context).devices),
                    onTap: () => context.go('/rooms/settings/devices'),
                    tileColor: activeRoute.startsWith('/rooms/settings/devices')
                        ? theme.colorScheme.surfaceContainerHigh
                        : null,
                  ),
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.forum_outlined,
                      CupertinoIcons.chat_bubble_2_fill,
                      CupertinoColors.systemGreen,
                    ),
                    trailing: chevron,
                    title: Text(L10n.of(context).chat),
                    onTap: () => context.go('/rooms/settings/chat'),
                    tileColor: activeRoute.startsWith('/rooms/settings/chat')
                        ? theme.colorScheme.surfaceContainerHigh
                        : null,
                  ),
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.shield_outlined,
                      CupertinoIcons.lock_shield_fill,
                      CupertinoColors.systemBlue,
                    ),
                    trailing: chevron,
                    title: Text(L10n.of(context).security),
                    onTap: () => context.go('/rooms/settings/security'),
                    tileColor:
                        activeRoute.startsWith('/rooms/settings/security')
                        ? theme.colorScheme.surfaceContainerHigh
                        : null,
                  ),
                ],
              ),
              SettingsSection(
                children: [
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.dns_outlined,
                      CupertinoIcons.globe,
                      CupertinoColors.systemTeal,
                    ),
                    trailing: chevron,
                    title: Text(
                      L10n.of(context).aboutHomeserver(
                        Matrix.of(context).client.userID?.domain ??
                            'homeserver',
                      ),
                    ),
                    onTap: () => context.go('/rooms/settings/homeserver'),
                    tileColor:
                        activeRoute.startsWith('/rooms/settings/homeserver')
                        ? theme.colorScheme.surfaceContainerHigh
                        : null,
                  ),
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.privacy_tip_outlined,
                      CupertinoIcons.hand_raised_fill,
                      CupertinoColors.systemBlue,
                    ),
                    title: Text(L10n.of(context).privacy),
                    onTap: () =>
                        launchUrlString(AppSettings.privacyPolicy.value),
                  ),
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.info_outline_rounded,
                      CupertinoIcons.info,
                      CupertinoColors.systemGrey,
                    ),
                    title: Text(L10n.of(context).about),
                    onTap: () => PlatformInfos.showDialog(context),
                  ),
                ],
              ),
              SettingsSection(
                children: [
                  ListTile(
                    leading: const SettingsIcon(
                      Icons.logout_outlined,
                      CupertinoIcons.square_arrow_right,
                      CupertinoColors.systemRed,
                    ),
                    title: Text(L10n.of(context).logout),
                    onTap: controller.logoutAction,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
