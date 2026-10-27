// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatWallpaper', () {
    test('Empty config has no wallpaper', () {
      expect(ChatWallpaper.tryFromJson({}), isNull);
      expect(ApplicationAccountConfig.fromJson({}).wallpaper, isNull);
    });

    test('Legacy config with only a url is an image', () {
      final wallpaper = ChatWallpaper.tryFromJson({
        'wallpaper_url': 'mxc://example.com/abc',
        'wallpaper_opacity': 0.5,
        'wallpaper_blur': 2,
      })!;
      expect(wallpaper.type, ChatWallpaperType.image);
      expect(wallpaper.url, Uri.parse('mxc://example.com/abc'));
      expect(wallpaper.opacity, 0.5);
      expect(wallpaper.blur, 2.0);
    });

    test('Explicit type wins over a leftover url', () {
      final wallpaper = ChatWallpaper.tryFromJson({
        'wallpaper_type': 'none',
        'wallpaper_url': 'mxc://example.com/abc',
      })!;
      expect(wallpaper.type, ChatWallpaperType.none);
      expect(wallpaper.url, isNull);
    });

    test('Image without url and unknown types are ignored', () {
      expect(ChatWallpaper.tryFromJson({'wallpaper_type': 'image'}), isNull);
      expect(ChatWallpaper.tryFromJson({'wallpaper_type': 'video'}), isNull);
    });

    test('Invalid opacity falls back to fully opaque', () {
      final wallpaper = ChatWallpaper.tryFromJson({
        'wallpaper_type': 'pattern',
        'wallpaper_opacity': 3.0,
      })!;
      expect(wallpaper.opacity, 1.0);
    });

    test('Survives a json round trip', () {
      final wallpaper = ChatWallpaper(
        type: ChatWallpaperType.image,
        url: Uri.parse('mxc://example.com/abc'),
        opacity: 0.7,
        blur: 3,
      );
      final parsed = ChatWallpaper.tryFromJson(wallpaper.toJson())!;
      expect(parsed.type, wallpaper.type);
      expect(parsed.url, wallpaper.url);
      expect(parsed.opacity, wallpaper.opacity);
      expect(parsed.blur, wallpaper.blur);

      final config = ApplicationAccountConfig.fromJson(
        const ApplicationAccountConfig(
          wallpaper: ChatWallpaper.pattern,
        ).toJson(),
      );
      expect(config.wallpaper?.type, ChatWallpaperType.pattern);
    });
  });
}
