// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:matrix/matrix.dart';

enum ChatWallpaperType { none, pattern, image }

class ChatWallpaper {
  final ChatWallpaperType type;

  /// Only set for [ChatWallpaperType.image].
  final Uri? url;
  final double opacity;
  final double blur;

  const ChatWallpaper({
    required this.type,
    this.url,
    this.opacity = 1,
    this.blur = 0,
  });

  static const ChatWallpaper none = ChatWallpaper(type: ChatWallpaperType.none);
  static const ChatWallpaper pattern = ChatWallpaper(
    type: ChatWallpaperType.pattern,
  );

  static double _sanitizedOpacity(double? opacity) {
    if (opacity == null) return 1;
    if (opacity > 1 || opacity < 0) return 1;
    return opacity;
  }

  /// Returns null if [json] does not contain a wallpaper. Configs without a
  /// `wallpaper_type` but with a `wallpaper_url` are treated as an image to
  /// stay compatible with older versions.
  static ChatWallpaper? tryFromJson(Map<String, Object?> json) {
    final urlString = json['wallpaper_url'];
    final url = urlString is String ? Uri.tryParse(urlString) : null;
    final type =
        ChatWallpaperType.values.asNameMap()[json['wallpaper_type']] ??
        (url == null ? null : ChatWallpaperType.image);
    if (type == null) return null;
    if (type == ChatWallpaperType.image && url == null) return null;
    return ChatWallpaper(
      type: type,
      url: type == ChatWallpaperType.image ? url : null,
      opacity: _sanitizedOpacity(
        json.tryGet<num>('wallpaper_opacity')?.toDouble(),
      ),
      blur: json.tryGet<num>('wallpaper_blur')?.toDouble() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'wallpaper_type': type.name,
    if (url != null) 'wallpaper_url': url.toString(),
    'wallpaper_opacity': opacity,
    'wallpaper_blur': blur,
  };

  ChatWallpaper copyWith({double? opacity, double? blur}) => ChatWallpaper(
    type: type,
    url: url,
    opacity: opacity ?? this.opacity,
    blur: blur ?? this.blur,
  );

  String localizedName(L10n l10n) => switch (type) {
    ChatWallpaperType.none => l10n.blankWallpaper,
    ChatWallpaperType.pattern => l10n.patternWallpaper,
    ChatWallpaperType.image => l10n.imageWallpaper,
  };
}

extension ChatWallpaperClientExtension on Client {
  /// The wallpaper of all chats which have no wallpaper of their own.
  ChatWallpaper get defaultChatWallpaper =>
      applicationAccountConfig.wallpaper ?? ChatWallpaper.none;

  Future<void> setDefaultChatWallpaper(ChatWallpaper wallpaper) =>
      updateApplicationAccountConfig(
        ApplicationAccountConfig(wallpaper: wallpaper),
      );

  /// Emits whenever the default wallpaper or the wallpaper of a chat changed.
  Stream<SyncUpdate> get onChatWallpaperChanged => onSync.stream.where(
    (update) =>
        (update.accountData?.any(
              (data) =>
                  data.type == ApplicationAccountConfigExtension.accountDataKey,
            ) ??
            false) ||
        (update.rooms?.join?.values.any(
              (room) =>
                  room.accountData?.any(
                    (data) =>
                        data.type == ChatWallpaperRoomExtension.accountDataKey,
                  ) ??
                  false,
            ) ??
            false),
  );
}

extension ChatWallpaperRoomExtension on Room {
  static const String accountDataKey = 'im.fluffychat.wallpaper';

  /// The wallpaper set only for this chat or null if it uses the default.
  ChatWallpaper? get customWallpaper =>
      ChatWallpaper.tryFromJson(roomAccountData[accountDataKey]?.content ?? {});

  ChatWallpaper get wallpaper => customWallpaper ?? client.defaultChatWallpaper;

  /// Pass null to use the default wallpaper again.
  Future<void> setCustomWallpaper(ChatWallpaper? wallpaper) =>
      client.setAccountDataPerRoom(
        client.userID!,
        id,
        accountDataKey,
        wallpaper?.toJson() ?? {},
      );
}
