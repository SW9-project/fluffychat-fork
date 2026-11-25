// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/personalization/assist/assist_actions.dart';
import 'package:fluffychat/personalization/model/app_change.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

/// The color state of the Style page, without its preferences.
class _Theme extends Fake implements ThemeController {
  @override
  Color? primaryColor;
  @override
  bool useSystemColor = false;

  @override
  Future<void> setPrimaryColor(Color? color) async {
    primaryColor = color;
    useSystemColor = color == null;
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_Theme';
}

void main() {
  late Client client;
  late Room room;
  late _Theme theme;
  late MatrixAssistActions actions;

  setUp(() async {
    client = await prepareTestClient();
    client.backgroundSync = false;
    // Account data written by the app comes back through the sync.
    FakeMatrixApi.client = client;
    room = client.rooms.firstWhere((r) => r.membership == Membership.join);
    theme = _Theme();
    actions = MatrixAssistActions(client, theme);
  });

  final red = Colors.red.toARGB32();
  final blue = Colors.blue.toARGB32();

  Future<void> apply(AppSetting setting, String? roomId, Object? value) =>
      actions.apply(AppChange(setting, roomId, value));

  test('a bubble color for one side keeps the other side', () async {
    await apply(AppSetting.ownBubbleColor, null, red);
    await apply(AppSetting.otherBubbleColor, null, blue);
    await apply(AppSetting.ownBubbleColor, null, null);
    expect(client.applicationAccountConfig.bubbleColor, isNull);
    expect(client.applicationAccountConfig.otherBubbleColor?.toARGB32(), blue);

    await apply(AppSetting.otherBubbleColor, room.id, red);
    await apply(AppSetting.ownBubbleColor, room.id, blue);
    expect(room.otherBubbleColor?.toARGB32(), red);
    expect(room.bubbleColor?.toARGB32(), blue);
    expect(actions.current(AppSetting.otherBubbleColor, room.id), red);
    // The chat's own colors leave the general ones alone.
    expect(client.applicationAccountConfig.bubbleColor, isNull);
    expect(actions.current(AppSetting.otherBubbleColor, null), blue);
  });

  test('wallpapers by name, and a chat back to the default', () async {
    await apply(AppSetting.wallpaper, null, 'pattern');
    expect(client.defaultChatWallpaper.type, ChatWallpaperType.pattern);
    expect(actions.current(AppSetting.wallpaper, null), 'pattern');
    await apply(AppSetting.wallpaper, null, 'none');
    expect(client.defaultChatWallpaper.type, ChatWallpaperType.none);
    await apply(AppSetting.wallpaper, null, 'pattern');
    await apply(AppSetting.wallpaper, null, null);
    expect(client.defaultChatWallpaper.type, ChatWallpaperType.none);

    await apply(AppSetting.wallpaper, room.id, 'pattern');
    expect(room.customWallpaper?.type, ChatWallpaperType.pattern);
    await apply(AppSetting.wallpaper, room.id, 'none');
    expect(room.customWallpaper?.type, ChatWallpaperType.none);
    await apply(AppSetting.wallpaper, room.id, null);
    expect(room.customWallpaper, isNull);
    expect(actions.current(AppSetting.wallpaper, room.id), isNull);
  });

  test('the app color is what the Style page ticks', () async {
    // A fresh install shows the app's own color.
    expect(
      actions.current(AppSetting.appColor, null),
      AppConfig.chatColor.toARGB32(),
    );
    await apply(AppSetting.appColor, null, red);
    expect(theme.primaryColor, same(Colors.red));
    expect(AppSettings.colorSchemeSeedInt.value, red);
    await apply(AppSetting.appColor, null, AppConfig.chatColor.toARGB32());
    expect(theme.primaryColor, same(AppConfig.chatColor));
    expect(theme.useSystemColor, isFalse);
  });

  test('undo puts the system accent color back', () async {
    await theme.setPrimaryColor(null);
    final before = actions.current(AppSetting.appColor, null);
    expect(before, isNull);
    await apply(AppSetting.appColor, null, red);
    expect(theme.useSystemColor, isFalse);
    await apply(AppSetting.appColor, null, before);
    expect(theme.useSystemColor, isTrue);
    expect(
      AppSettings.colorSchemeSeedInt.value,
      AppSettings.colorSchemeSeedInt.defaultValue,
    );
  });
}
