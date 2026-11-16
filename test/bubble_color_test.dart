// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  test('bubble color survives the account data round trip', () {
    const color = Color(0xFF2196F3);
    const other = Color(0xFFE91E63);
    final json = const ApplicationAccountConfig(
      bubbleColor: color,
      otherBubbleColor: other,
    ).toJson();
    expect(ApplicationAccountConfig.fromJson(json).bubbleColor, color);
    expect(ApplicationAccountConfig.fromJson(json).otherBubbleColor, other);
    expect(
      ApplicationAccountConfig.fromJson(
        const ApplicationAccountConfig().toJson(),
      ).bubbleColor,
      isNull,
    );
  });

  test('custom bubble color overrides the default with readable text', () {
    final light = ThemeData(brightness: Brightness.light);
    expect(light.withBubbleColors(null, null).bubbleColor, light.bubbleColor);

    final dark = light.withBubbleColors(const Color(0xFF1A237E), null);
    expect(dark.bubbleColor, const Color(0xFF1A237E));
    expect(dark.onBubbleColor, Colors.white);
    expect(
      light.withBubbleColors(const Color(0xFFFFEB3B), null).onBubbleColor,
      Colors.black,
    );
  });

  test('other bubbles get their own color but never the own one', () {
    final light = ThemeData(brightness: Brightness.light);
    const blue = Color(0xFF2196F3);
    final both = light.withBubbleColors(null, const Color(0xFF1A237E));
    expect(both.otherBubbleColor, const Color(0xFF1A237E));
    expect(both.onOtherBubbleColor, Colors.white);

    final clash = light.withBubbleColors(blue, blue);
    expect(clash.bubbleColor, blue);
    expect(clash.otherBubbleColor, light.otherBubbleColor);
  });

  test('bubbles follow the platform', () {
    final android = ThemeData(platform: TargetPlatform.android);
    final ios = ThemeData(platform: TargetPlatform.iOS);
    expect(android.bubbleColor, android.colorScheme.primaryContainer);
    expect(android.onBubbleColor, android.colorScheme.onPrimaryContainer);
    expect(ios.bubbleColor, ios.colorScheme.primary);
    expect(ios.onBubbleColor, ios.colorScheme.onPrimary);

    // Google Messages tightens the corners between grouped messages, iOS
    // keeps them round.
    const grouped = MessageBubbleBorder(ownMessage: true, groupedAbove: true);
    expect(grouped.borderRadius.topRight, const Radius.circular(4));
    expect(grouped.borderRadius.topLeft, const Radius.circular(20));
    const groupedIos = MessageBubbleBorder(
      ownMessage: true,
      cupertino: true,
      groupedAbove: true,
    );
    expect(groupedIos.borderRadius.topRight, const Radius.circular(18));
  });

  test('a chat wallpaper overrides the general one', () async {
    final room = Room(
      id: '!chat:example.org',
      client: await prepareTestClient(),
    );
    expect(room.wallpaperUrl, isNull);
    room.roomAccountData[RoomBubbleColorExtension.accountDataKey] = BasicEvent(
      type: RoomBubbleColorExtension.accountDataKey,
      content: {
        'wallpaper_url': 'mxc://example.org/chat',
        'wallpaper_opacity': 0.3,
      },
    );
    expect(room.wallpaperUrl, Uri.parse('mxc://example.org/chat'));
    expect(room.ownWallpaperUrl, Uri.parse('mxc://example.org/chat'));
    expect(room.wallpaperOpacity, 0.3);
    expect(room.wallpaperBlur, 0.0);
  });
}
