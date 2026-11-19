// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/simple_view_conversation_source.dart';
import 'package:fluffychat/personalization/simplified_interface_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

import '../utils/test_client.dart';

void main() {
  test('example chats fill the preview without touching the account', () async {
    final client = await prepareTestClient();
    final before = client.rooms.length;
    final rooms = simpleViewExampleRooms(
      client,
      const SimplifiedInterfaceL10n('es'),
    );
    // Enough examples for the full view; simple view shows fewer.
    expect(rooms.length, simpleViewPreviewCount(simple: false));
    expect(simpleViewPreviewCount(simple: true), 2);
    expect(rooms.take(2).map((r) => r.getLocalizedDisplayname()), [
      'Ana',
      'Luis',
    ]);
    expect(rooms.first.lastEvent?.body, '¡Hola!');
    // The sender is known, so the list does not fetch a profile.
    final last = rooms.first.lastEvent!;
    expect(rooms.first.getState('m.room.member', last.senderId), isNotNull);
    expect(client.rooms.length, before);
  });
}
