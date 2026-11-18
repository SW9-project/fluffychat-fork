// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_wallpaper/wallpaper_editor.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/bubble_color_picker.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings_section.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/app_config.dart';
import 'settings_style.dart';

class SettingsStyleView extends StatelessWidget {
  final SettingsStyleController controller;

  const SettingsStyleView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const colorPickerSize = 32.0;
    final client = Matrix.of(context).client;
    final background = theme.cupertinoStyle
        ? SettingsSection.backgroundColor(theme)
        : theme.colorScheme.surface;
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.cupertinoStyle ? background : null,
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: Text(L10n.of(context).changeTheme),
      ),
      backgroundColor: background,
      body: MaxWidthBody(
        child: SettingsList(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: theme.cupertinoStyle
                  ? CupertinoSlidingSegmentedControl<ThemeMode>(
                      groupValue: controller.currentTheme,
                      onValueChanged: (mode) {
                        if (mode != null) controller.switchTheme(mode);
                      },
                      children: {
                        ThemeMode.light: Text(l10n.lightTheme),
                        ThemeMode.dark: Text(l10n.darkTheme),
                        ThemeMode.system: Text(l10n.systemTheme),
                      },
                    )
                  : SegmentedButton<ThemeMode>(
                      selected: {controller.currentTheme},
                      onSelectionChanged: (selected) =>
                          controller.switchTheme(selected.single),
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(L10n.of(context).lightTheme),
                          icon: const Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(L10n.of(context).darkTheme),
                          icon: const Icon(Icons.dark_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(L10n.of(context).systemTheme),
                          icon: const Icon(Icons.auto_mode_outlined),
                        ),
                      ],
                    ),
            ),
            Divider(color: theme.dividerColor),
            SettingsHeader(L10n.of(context).setColorTheme),
            DynamicColorBuilder(
              builder: (light, dark) {
                final systemColor =
                    Theme.of(context).brightness == Brightness.light
                    ? light?.primary
                    : dark?.primary;
                final colors = [null, AppConfig.chatColor, ...Colors.primaries];
                if (systemColor == null) {
                  colors.remove(null);
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                  ),
                  itemCount: colors.length,
                  itemBuilder: (context, i) {
                    final color = colors[i];
                    return Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Tooltip(
                        message: color == null
                            ? L10n.of(context).systemTheme
                            : '#${color.hexValue.toRadixString(16).toUpperCase()}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(colorPickerSize),
                          onTap: () => controller.setChatColor(color),
                          child: Material(
                            color: color ?? systemColor,
                            elevation: 6,
                            borderRadius: BorderRadius.circular(
                              colorPickerSize,
                            ),
                            child: SizedBox(
                              width: colorPickerSize,
                              height: colorPickerSize,
                              child: controller.currentColor == color
                                  ? Center(
                                      child: Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            StreamBuilder(
              stream: client.onChatWallpaperChanged,
              builder: (context, _) =>
                  ChatStylePreview(wallpaper: client.defaultChatWallpaper),
            ),
            Divider(color: theme.dividerColor),
            SettingsHeader(L10n.of(context).messagesStyle),
            StreamBuilder(
              stream: client.onSync.stream.where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) =>
                          accountData.type ==
                          ApplicationAccountConfigExtension.accountDataKey,
                    ) ??
                    false,
              ),
              builder: (context, snapshot) {
                final accountConfig = client.applicationAccountConfig;
                return Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: [
                    ListTile(title: Text(L10n.of(context).ownBubbleColor)),
                    BubbleColorPicker(
                      selected: accountConfig.bubbleColor,
                      disabled: accountConfig.otherBubbleColor,
                      onSelected: (color) => controller.setBubbleColors(
                        color,
                        accountConfig.otherBubbleColor,
                      ),
                      nullLabel: L10n.of(context).defaultBubbleColor,
                    ),
                    ListTile(title: Text(L10n.of(context).otherBubbleColor)),
                    BubbleColorPicker(
                      selected: accountConfig.otherBubbleColor,
                      disabled: accountConfig.bubbleColor,
                      onSelected: (color) => controller.setBubbleColors(
                        accountConfig.bubbleColor,
                        color,
                      ),
                      nullLabel: L10n.of(context).defaultBubbleColor,
                    ),
                  ],
                );
              },
            ),
            const WallpaperEditor(showPreview: false),
            Divider(color: theme.dividerColor),
            SettingsHeader(L10n.of(context).chatWallpapers),
            StreamBuilder(
              stream: client.onChatWallpaperChanged,
              builder: (context, _) {
                final rooms = client.rooms
                    .where((room) => room.customWallpaper != null)
                    .toList();
                return Column(
                  mainAxisSize: .min,
                  children: [
                    for (final room in rooms)
                      _ChatWallpaperListTile(
                        room: room,
                        onReset: () => controller.resetChatWallpaper(room),
                      ),
                  ],
                );
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.surfaceContainer,
                foregroundColor: theme.colorScheme.onSurface,
                child: const Icon(Icons.add_outlined),
              ),
              title: Text(L10n.of(context).setWallpaperForChat),
              onTap: controller.setChatWallpaper,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ChatWallpaperListTile extends StatelessWidget {
  final Room room;
  final VoidCallback onReset;

  const _ChatWallpaperListTile({required this.room, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    return ListTile(
      leading: Avatar(
        mxContent: room.avatar,
        name: displayname,
        size: Avatar.defaultSize * 0.75,
      ),
      title: Text(displayname, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(room.wallpaper.localizedName(L10n.of(context))),
      trailing: IconButton(
        tooltip: L10n.of(context).useDefaultWallpaper,
        icon: const Icon(Icons.delete_outlined),
        color: theme.colorScheme.error,
        onPressed: onReset,
      ),
      onTap: () => context.push('/rooms/settings/style/wallpaper/${room.id}'),
    );
  }
}
