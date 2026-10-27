// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat_wallpaper.dart';
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
      ).toJson(),
    );
  }
}

class ApplicationAccountConfig {
  /// The default wallpaper for all chats without a wallpaper of their own.
  final ChatWallpaper? wallpaper;

  const ApplicationAccountConfig({this.wallpaper});

  factory ApplicationAccountConfig.fromJson(Map<String, dynamic> json) =>
      ApplicationAccountConfig(wallpaper: ChatWallpaper.tryFromJson(json));

  Map<String, dynamic> toJson() => {...?wallpaper?.toJson()};
}
