// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  bool isLogged() => false;
}

void main() {
  // `set_gesture autoplay_gifs` changes this setting, so the timeline must
  // follow it.
  testWidgets('timeline images play only when autoplay is on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    final sticker = Event(
      type: EventTypes.Sticker,
      content: {'body': 'cat', 'url': 'mxc://example.org/cat'},
      eventId: r'$sticker',
      senderId: '@simon:example.org',
      originServerTs: DateTime(2026),
      room: Room(id: '!room:example.org', client: _Client()),
    );
    Future<bool> autoplay() async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ImageBubble(sticker))),
      );
      return tester.widget<MxcImage>(find.byType(MxcImage)).autoplay;
    }

    expect(await autoplay(), isTrue);
    await AppSettings.autoplayImages.setItem(false);
    expect(await autoplay(), isFalse);
  });
}
