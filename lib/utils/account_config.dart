// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

extension ApplicationAccountConfigExtension on Client {
  static const String accountDataKey = 'im.fluffychat.account_config';

  ApplicationAccountConfig get applicationAccountConfig =>
      ApplicationAccountConfig.fromJson(
        accountData[accountDataKey]?.content ?? {},
      );

  Future<void> setApplicationAccountConfig(ApplicationAccountConfig config) =>
      setAccountData(userID!, accountDataKey, config.toJson());

  /// Only updates the specified values in ApplicationAccountConfig
  Future<void> updateApplicationAccountConfig(ApplicationAccountConfig config) {
    final currentConfig = applicationAccountConfig;
    return setAccountData(
      userID!,
      accountDataKey,
      ApplicationAccountConfig(
        wallpaper: config.wallpaper ?? currentConfig.wallpaper,
        bubbleColor: config.bubbleColor ?? currentConfig.bubbleColor,
        otherBubbleColor:
            config.otherBubbleColor ?? currentConfig.otherBubbleColor,
      ).toJson(),
    );
  }
}

class ApplicationAccountConfig {
  /// The default wallpaper for all chats without a wallpaper of their own.
  final ChatWallpaper? wallpaper;

  /// Color of own message bubbles, null for the default.
  final Color? bubbleColor;

  /// Color of other people's message bubbles, null for the default.
  final Color? otherBubbleColor;

  const ApplicationAccountConfig({
    this.wallpaper,
    this.bubbleColor,
    this.otherBubbleColor,
  });

  factory ApplicationAccountConfig.fromJson(Map<String, dynamic> json) =>
      ApplicationAccountConfig(
        wallpaper: ChatWallpaper.tryFromJson(json),
        bubbleColor: _color(json.tryGet<int>('bubble_color')),
        otherBubbleColor: _color(json.tryGet<int>('other_bubble_color')),
      );

  Map<String, dynamic> toJson() => {
    ...?wallpaper?.toJson(),
    if (bubbleColor != null) 'bubble_color': bubbleColor!.toARGB32(),
    if (otherBubbleColor != null)
      'other_bubble_color': otherBubbleColor!.toARGB32(),
  };
}

Color? _color(int? argb) => argb == null ? null : Color(argb);

/// Per chat overrides of [ApplicationAccountConfig], stored in the room
/// account data so they sync between devices.
extension RoomBubbleColorExtension on Room {
  static const String accountDataKey = 'im.fluffychat.room_config';

  Map<String, Object?> get _roomConfig =>
      roomAccountData[accountDataKey]?.content ?? const {};

  /// Fires when the general or this chat's config changes.
  Stream<SyncUpdate> get onConfigChange => client.onSync.stream.where(
    (update) =>
        (update.accountData?.any(
              (e) => e.type == ApplicationAccountConfigExtension.accountDataKey,
            ) ??
            false) ||
        (update.rooms?.join?[id]?.accountData?.any(
              (e) => e.type == accountDataKey,
            ) ??
            false),
  );

  /// A missing key follows the general color, a null value is the default.
  Color? _roomColor(String key, Color? general) {
    final content = _roomConfig;
    if (!content.containsKey(key)) return general;
    return _color(content.tryGet<int>(key));
  }

  /// The bubble colors of this chat, null for the app default.
  Color? get bubbleColor =>
      _roomColor('bubble_color', client.applicationAccountConfig.bubbleColor);
  Color? get otherBubbleColor => _roomColor(
    'other_bubble_color',
    client.applicationAccountConfig.otherBubbleColor,
  );

  /// Colors equal to the general ones are not stored, so the chat keeps
  /// following the general setting.
  Future<void> setBubbleColors(Color? own, Color? other) {
    final general = client.applicationAccountConfig;
    final content = Map<String, Object?>.of(_roomConfig)
      ..remove('bubble_color')
      ..remove('other_bubble_color');
    if (own?.toARGB32() != general.bubbleColor?.toARGB32()) {
      content['bubble_color'] = own?.toARGB32();
    }
    if (other?.toARGB32() != general.otherBubbleColor?.toARGB32()) {
      content['other_bubble_color'] = other?.toARGB32();
    }
    return client.setAccountDataPerRoom(
      client.userID!,
      id,
      accountDataKey,
      content,
    );
  }

  /// Writes [changes] over the stored config; a null value removes the key.
  Future<void> setRoomConfig(Map<String, Object?> changes) {
    final content = Map<String, Object?>.of(_roomConfig);
    changes.forEach(
      (key, value) =>
          value == null ? content.remove(key) : content[key] = value,
    );
    return client.setAccountDataPerRoom(
      client.userID!,
      id,
      accountDataKey,
      content,
    );
  }
}
