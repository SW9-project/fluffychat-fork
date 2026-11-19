// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../model/app_change.dart';

/// Reads and applies the app settings an [AppChange] is about, for the
/// Assist tab.
abstract class AssistActions {
  /// The value [setting] has now, in the shape of [AppChange.value].
  Object? current(AppSetting setting, String? roomId);

  Future<void> apply(AppChange change);
}

/// The app's own settings and the chats of [client], changed as the
/// settings pages and the chat list change them.
class MatrixAssistActions implements AssistActions {
  final Client client;
  final void Function(Color?) setPrimaryColor;

  const MatrixAssistActions(this.client, this.setPrimaryColor);

  static const _seed = AppSettings.colorSchemeSeedInt;

  @override
  Object? current(AppSetting setting, String? roomId) {
    final room = roomId == null ? null : client.getRoomById(roomId);
    final config = client.applicationAccountConfig;
    return switch (setting) {
      AppSetting.ownBubbleColor =>
        (roomId == null ? config.bubbleColor : room?.bubbleColor)?.toARGB32(),
      AppSetting.otherBubbleColor =>
        (roomId == null ? config.otherBubbleColor : room?.otherBubbleColor)
            ?.toARGB32(),
      // shortcut: the default seed reads as the default color, also when it
      // was picked by hand; store the choice apart if that ever matters.
      AppSetting.appColor =>
        _seed.value == _seed.defaultValue ? null : _seed.value,
      AppSetting.wallpaper => _wallpaper(
        roomId == null ? client.defaultChatWallpaper : room?.customWallpaper,
      ),
      AppSetting.swipeToReply => AppSettings.swipeToReply.value,
      AppSetting.doubleTapToReact => AppSettings.doubleTapToReact.value,
      AppSetting.sendOnEnter => AppSettings.sendOnEnter.value,
      AppSetting.autoplayGifs => AppSettings.autoplayImages.value,
      AppSetting.pinned => room?.isFavourite,
      // shortcut: "no notifications" reads as muted, so its undo is mentions
      // only; return the PushRuleState if that matters.
      AppSetting.muted =>
        room == null ? null : room.pushRuleState != PushRuleState.notify,
    };
  }

  /// A wallpaper by name, or whole when the name would lose something, such
  /// as an image, so undo can put it back.
  static Object? _wallpaper(ChatWallpaper? wallpaper) =>
      wallpaper == null ||
          wallpaper.type == ChatWallpaperType.image ||
          wallpaper.opacity != 1 ||
          wallpaper.blur != 0
      ? wallpaper
      : wallpaper.type.name;

  @override
  Future<void> apply(AppChange change) async {
    final AppChange(:setting, :roomId, :value) = change;
    final room = roomId == null ? null : client.getRoomById(roomId);
    if (roomId != null && room == null) throw StateError('No such chat');
    final color = value is int ? Color(value) : null;
    final on = value == true;
    switch (setting) {
      case AppSetting.ownBubbleColor || AppSetting.otherBubbleColor:
        final own = setting == AppSetting.ownBubbleColor;
        if (room != null) {
          return room.setBubbleColors(
            own ? color : room.bubbleColor,
            own ? room.otherBubbleColor : color,
          );
        }
        final config = client.applicationAccountConfig;
        // Not updateApplicationAccountConfig: it can not reset a value to null.
        return client.setApplicationAccountConfig(
          ApplicationAccountConfig(
            wallpaper: config.wallpaper,
            bubbleColor: own ? color : config.bubbleColor,
            otherBubbleColor: own ? config.otherBubbleColor : color,
          ),
        );
      case AppSetting.appColor:
        await _seed.setItem(color?.toARGB32() ?? _seed.defaultValue);
        setPrimaryColor(color);
      case AppSetting.wallpaper:
        final wallpaper = switch (value) {
          final ChatWallpaper wallpaper => wallpaper,
          'none' => ChatWallpaper.none,
          'pattern' => ChatWallpaper.pattern,
          _ => null,
        };
        if (room != null) return room.setCustomWallpaper(wallpaper);
        return client.setDefaultChatWallpaper(wallpaper ?? ChatWallpaper.none);
      case AppSetting.swipeToReply:
        return AppSettings.swipeToReply.setItem(on);
      case AppSetting.doubleTapToReact:
        return AppSettings.doubleTapToReact.setItem(on);
      case AppSetting.sendOnEnter:
        return AppSettings.sendOnEnter.setItem(on);
      case AppSetting.autoplayGifs:
        return AppSettings.autoplayImages.setItem(on);
      case AppSetting.pinned:
        return room!.setFavourite(on);
      case AppSetting.muted:
        return room!.setPushRuleState(
          on ? PushRuleState.mentionsOnly : PushRuleState.notify,
        );
    }
  }
}
