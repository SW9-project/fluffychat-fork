// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

<<<<<<< Updated upstream
=======
import 'dart:ui';

import 'package:cupertino_ui/cupertino_ui.dart';
>>>>>>> Stashed changes
import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_wallpaper/wallpaper_editor.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/bubble_color_picker.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
<<<<<<< Updated upstream
import 'package:go_router/go_router.dart';
=======
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/settings_section.dart';
>>>>>>> Stashed changes
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
            Divider(color: theme.dividerColor),
<<<<<<< Updated upstream
            ListTile(
              title: Text(
                L10n.of(context).messagesStyle,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const WallpaperEditor(),
            // The font size slider moved to the accessibility settings.
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).chatWallpapers,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            StreamBuilder(
              stream: client.onChatWallpaperChanged,
              builder: (context, _) {
                final rooms = client.rooms
                    .where((room) => room.customWallpaper != null)
                    .toList();
=======
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
                final previewTheme = theme.withBubbleColors(
                  accountConfig.bubbleColor,
                  accountConfig.otherBubbleColor,
                );

>>>>>>> Stashed changes
                return Column(
                  mainAxisSize: .min,
                  children: [
                    for (final room in rooms)
                      _ChatWallpaperListTile(
                        room: room,
                        onReset: () => controller.resetChatWallpaper(room),
                      ),
<<<<<<< Updated upstream
=======
                      child: AnimatedContainer(
                        duration: FluffyThemes.animationDuration,
                        curve: FluffyThemes.animationCurve,
                        decoration: const BoxDecoration(),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (accountConfig.wallpaperUrl != null)
                              Opacity(
                                opacity: controller.wallpaperOpacity,
                                child: ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: controller.wallpaperBlur,
                                    sigmaY: controller.wallpaperBlur,
                                  ),
                                  child: MxcImage(
                                    key: ValueKey(accountConfig.wallpaperUrl),
                                    uri: accountConfig.wallpaperUrl,
                                    fit: BoxFit.cover,
                                    isThumbnail: true,
                                    width: FluffyThemes.columnWidth * 2,
                                    height: 212,
                                  ),
                                ),
                              ),
                            Column(
                              mainAxisSize: .min,
                              children: [
                                const SizedBox(height: 16),
                                StateMessage(
                                  Event(
                                    eventId: 'style_dummy',
                                    room: Room(
                                      id: '!style_dummy',
                                      client: client,
                                    ),
                                    content: {'membership': 'join'},
                                    type: EventTypes.RoomMember,
                                    senderId: client.userID!,
                                    originServerTs: DateTime.now(),
                                    stateKey: client.userID,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: 12 + 12 + Avatar.defaultSize,
                                    right: 12,
                                    top: accountConfig.wallpaperUrl == null
                                        ? 0
                                        : 12,
                                    bottom: 12,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: previewTheme.bubbleColor,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor',
                                        style: TextStyle(
                                          color: previewTheme.onBubbleColor,
                                          fontSize: AppConfig.messageFontSize,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: 12,
                                      left: 12,
                                      top: accountConfig.wallpaperUrl == null
                                          ? 0
                                          : 12,
                                      bottom: 12,
                                    ),
                                    child: Material(
                                      color: previewTheme.otherBubbleColor,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'Lorem ipsum dolor sit amet',
                                          style: TextStyle(
                                            color:
                                                previewTheme.onOtherBubbleColor,
                                            fontSize: AppConfig.messageFontSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(color: theme.dividerColor),
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
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          foregroundColor:
                              theme.colorScheme.onSecondaryContainer,
                        ),
                        onPressed: controller.setWallpaper,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(L10n.of(context).setWallpaper),
                      ),
                      trailing: accountConfig.wallpaperUrl == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outlined),
                              color: theme.colorScheme.error,
                              onPressed: controller.deleteChatWallpaper,
                            ),
                    ),
                    if (accountConfig.wallpaperUrl != null) ...[
                      ListTile(title: Text(L10n.of(context).opacity)),
                      Slider.adaptive(
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperOpacity,
                        onChanged: controller.updateWallpaperOpacity,
                        onChangeEnd: controller.saveWallpaperOpacity,
                      ),
                      ListTile(title: Text(L10n.of(context).blur)),
                      Slider.adaptive(
                        min: 0.0,
                        max: 10.0,
                        divisions: 10,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperBlur,
                        onChanged: controller.updateWallpaperBlur,
                        onChangeEnd: controller.saveWallpaperBlur,
                      ),
                    ],
>>>>>>> Stashed changes
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
