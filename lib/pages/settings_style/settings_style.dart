// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_wallpaper/chat_picker_dialog.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'settings_style_view.dart';

class SettingsStyle extends StatefulWidget {
  const SettingsStyle({super.key});

  @override
  SettingsStyleController createState() => SettingsStyleController();
}

class SettingsStyleController extends State<SettingsStyle> {
  void setChatColor(Color? color) {
    AppSettings.colorSchemeSeedInt.setItem(
      color?.toARGB32() ?? AppSettings.colorSchemeSeedInt.defaultValue,
    );
    ThemeController.of(context).setPrimaryColor(color);
  }

  Future<void> setChatWallpaper() async {
    final roomId = await showChatPickerDialog(
      context: context,
      title: L10n.of(context).setWallpaperForChat,
    );
    if (roomId == null || !mounted) return;
    context.push('/rooms/settings/style/wallpaper/$roomId');
  }

  void resetChatWallpaper(Room room) => showFutureLoadingDialog(
    context: context,
    future: () => room.setCustomWallpaper(null),
  );

  ThemeMode get currentTheme => ThemeController.of(context).themeMode;
  Color? get currentColor {
    final themeController = ThemeController.of(context);
    return themeController.primaryColor ??
        (themeController.useSystemColor ? null : AppConfig.chatColor);
  }

  void switchTheme(ThemeMode? newTheme) {
    if (newTheme == null) return;
    switch (newTheme) {
      case ThemeMode.light:
        ThemeController.of(context).setThemeMode(ThemeMode.light);
        break;
      case ThemeMode.dark:
        ThemeController.of(context).setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.system:
        ThemeController.of(context).setThemeMode(ThemeMode.system);
        break;
    }
    setState(() {});
  }

  Future<void> changeFontSizeFactor(double d) async {
    await AppSettings.fontSizeFactor.setItem(d);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsStyleView(this);
}
