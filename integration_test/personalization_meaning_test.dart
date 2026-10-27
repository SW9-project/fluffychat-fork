// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Phase 4 check with two accounts on a local Synapse
// (scripts/prepare_integration_test.sh, test users from
// integration_test/data/integration_users.env). Alice sends an annotated
// message in an encrypted room; the server only sees ciphertext; Bob decrypts
// it and reads the meaning; an edit carries new meaning in m.new_content.
//
// Run on an Android emulator (the homeserver is the host at 10.0.2.2):
//   flutter test integration_test/personalization_meaning_test.dart

import 'package:collection/collection.dart';
import 'package:fluffychat/personalization/meaning/annotated_send.dart';
import 'package:fluffychat/personalization/meaning/meaning_rules.dart';
import 'package:fluffychat/personalization/meaning/message_meaning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/environment_constants.dart';

// ignore: avoid_print
void report(String line) => print('[meaning] $line');

Future<Client> login(String user, String password) async {
  final client = Client(
    'meaning-test-$user',
    database: await MatrixSdkDatabase.init(
      'meaning-test-$user',
      database: await createDatabaseFactoryFfi().openDatabase(
        inMemoryDatabasePath,
      ),
    ),
    shareKeysWith: ShareKeysWith.all,
  );
  await client.checkHomeserver(Uri.http(homeserver));
  await client.login(
    LoginType.mLoginPassword,
    identifier: AuthenticationUserIdentifier(user: user),
    password: password,
    initialDeviceDisplayName: 'Phase 4 test',
  );
  return client;
}

Future<T> waitFor<T>(
  String what,
  Future<T?> Function() check, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final result = await check();
    if (result != null) return result;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('Timed out waiting for $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('annotated messages between two accounts', (tester) async {
    await tester.runAsync(() async {
      await vod.init();
      final alice = await login(user1Name, user1Pw);
      final bob = await login(user2Name, user2Pw);
      report('logged in ${alice.userID} and ${bob.userID}');

      final roomId = await alice.createGroupChat(
        groupName: 'Phase 4 test',
        invite: [bob.userID!],
        enableEncryption: true,
        preset: CreateRoomPreset.privateChat,
      );
      await waitFor('bob invite', () async => bob.getRoomById(roomId));
      await bob.getRoomById(roomId)!.join();
      final aliceRoom = alice.getRoomById(roomId)!;
      await waitFor(
        'bob joined',
        () async =>
            aliceRoom
                    .getState(EventTypes.RoomMember, bob.userID!)
                    ?.content['membership'] ==
                'join'
            ? true
            : null,
      );
      expect(aliceRoom.encrypted, isTrue);
      report('encrypted room $roomId');

      // Alice writes; the rules propose the meaning, which she confirms.
      const text = 'Ses vi i morgen kl. 14?';
      final meaning = MeaningRules.propose(text, DateTime.now());
      expect(meaning.intent, MessageIntent.question);
      expect(meaning.times.single.text, 'i morgen kl. 14');
      final eventId = (await sendAnnotatedText(
        aliceRoom,
        text,
        meaning: meaning,
      ))!;
      report('sent $eventId with ${meaning.toJson()}');

      // The server only has ciphertext: no body, no meaning in plaintext.
      final raw = await alice.getOneRoomEvent(roomId, eventId);
      expect(raw.type, EventTypes.Encrypted);
      expect(raw.content.containsKey(MessageMeaning.namespace), isFalse);
      expect(raw.content.containsKey('body'), isFalse);
      expect(raw.content['ciphertext'], isNotNull);
      report('server sees ${raw.type}, keys ${raw.content.keys.toList()}');

      // Bob decrypts the message and reads the meaning.
      final bobRoom = bob.getRoomById(roomId)!;
      final received = await waitFor('bob decrypts', () async {
        final event = await bobRoom.getEventById(eventId);
        if (event == null) return null;
        final decrypted = event.type == EventTypes.Encrypted
            ? await bob.encryption!.decryptRoomEvent(event)
            : event;
        return decrypted.type == EventTypes.Message ? decrypted : null;
      });
      expect(received.body, text);
      expect(MessageMeaning.fromContent(received.content), meaning);
      report(
        'bob decrypted "${received.body}" with ${received.content[MessageMeaning.namespace]}',
      );

      // An edit carries its own meaning in m.new_content.
      const editedText = 'Ses vi i overmorgen kl. 15 i stedet?';
      final editedMeaning = MeaningRules.propose(editedText, DateTime.now());
      final editId = (await sendAnnotatedText(
        aliceRoom,
        editedText,
        meaning: editedMeaning,
        editEventId: eventId,
      ))!;
      final timeline = await bobRoom.getTimeline();
      final display = await waitFor('bob sees the edit', () async {
        final original = timeline.events.firstWhereOrNull(
          (e) => e.eventId == eventId,
        );
        if (original == null) {
          await timeline.requestHistory();
          return null;
        }
        final shown = original.getDisplayEvent(timeline);
        return shown.body == editedText ? shown : null;
      });
      expect(MessageMeaning.fromContent(display.content), editedMeaning);
      final editEvent = await waitFor('bob decrypts the edit', () async {
        final event = await bobRoom.getEventById(editId);
        if (event == null) return null;
        final decrypted = event.type == EventTypes.Encrypted
            ? await bob.encryption!.decryptRoomEvent(event)
            : event;
        return decrypted.type == EventTypes.Message ? decrypted : null;
      });
      final newContent = editEvent.content['m.new_content'] as Map;
      expect(newContent[MessageMeaning.namespace], editedMeaning.toJson());
      expect(
        (editEvent.content['m.relates_to'] as Map)[MessageMeaning.namespace],
        isNull,
      );
      report(
        'edit $editId shows "${display.body}" with ${newContent[MessageMeaning.namespace]}',
      );

      timeline.cancelSubscriptions();
      await alice.dispose(closeDatabase: true);
      await bob.dispose(closeDatabase: true);
      report('PASSED');
    });
  });
}
