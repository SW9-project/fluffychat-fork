// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_rtc_call_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

const _roomId = '!room:example.com';
const _alice = '@alice:example.com';
const _bob = '@bob:example.com';
const _carol = '@carol:example.com';

final _start = DateTime(2026, 10, 26, 12);

var _eventCounter = 0;

MatrixEvent _join(
  String userId,
  Duration at, {
  MatrixRtcCallIntent intent = MatrixRtcCallIntent.video,
  Duration expires = const Duration(hours: 4),
}) => MatrixEvent(
  type: MatrixRtcCallMember.eventType,
  content: {
    'application': 'm.call',
    'call_id': '',
    'device_id': 'DEVICE',
    'expires': expires.inMilliseconds,
    'm.call.intent': intent.name,
    'scope': 'm.room',
    'created_at': _start.add(at).millisecondsSinceEpoch,
  },
  senderId: userId,
  stateKey: '_${userId}_DEVICE_m.call',
  eventId: '\$${_eventCounter++}',
  originServerTs: _start.add(at),
);

MatrixEvent _leave(String userId, Duration at) => MatrixEvent(
  type: MatrixRtcCallMember.eventType,
  content: {},
  senderId: userId,
  stateKey: '_${userId}_DEVICE_m.call',
  eventId: '\$${_eventCounter++}',
  originServerTs: _start.add(at),
);

List<CallLogEntry> _callLog(List<MatrixEvent> events, {Duration? now}) =>
    callLogFromCallMemberEvents(
      _roomId,
      // The server returns the newest events first:
      events.reversed,
      ownUserId: _alice,
      now: _start.add(now ?? const Duration(days: 1)),
    );

void main() {
  group('Call log from call member events', () {
    test('Outgoing call which has been answered', () {
      final entries = _callLog([
        _join(_alice, Duration.zero, intent: MatrixRtcCallIntent.voice),
        _join(_bob, const Duration(seconds: 10)),
        _leave(_bob, const Duration(minutes: 3)),
        _leave(_alice, const Duration(minutes: 3, seconds: 5)),
      ]);
      expect(entries.length, 1);
      final entry = entries.single;
      expect(entry.direction, CallLogDirection.outgoing);
      expect(entry.initiatorId, _alice);
      expect(entry.intent, MatrixRtcCallIntent.voice);
      expect(entry.participantIds, {_alice, _bob});
      expect(entry.start, _start);
      expect(entry.duration, const Duration(minutes: 3, seconds: 5));
      expect(entry.isOngoing, false);
    });

    test('Incoming and missed calls', () {
      final entries = _callLog([
        _join(_bob, Duration.zero),
        _join(_alice, const Duration(seconds: 5)),
        _leave(_alice, const Duration(minutes: 1)),
        _leave(_bob, const Duration(minutes: 1, seconds: 1)),
        _join(_bob, const Duration(hours: 1)),
        _leave(_bob, const Duration(hours: 1, seconds: 30)),
      ]);
      expect(entries.map((entry) => entry.direction), [
        CallLogDirection.incoming,
        CallLogDirection.missed,
      ]);
      expect(entries.last.duration, const Duration(seconds: 30));
    });

    test('Group call ends when the last participant leaves', () {
      final entries = _callLog([
        _join(_bob, Duration.zero),
        _join(_carol, const Duration(minutes: 1)),
        _leave(_bob, const Duration(minutes: 2)),
        _join(_alice, const Duration(minutes: 3)),
        _leave(_carol, const Duration(minutes: 4)),
        _leave(_alice, const Duration(minutes: 5)),
      ]);
      expect(entries.length, 1);
      expect(entries.single.initiatorId, _bob);
      expect(entries.single.participantIds, {_alice, _bob, _carol});
      expect(entries.single.direction, CallLogDirection.incoming);
      expect(entries.single.duration, const Duration(minutes: 5));
    });

    test('Expired memberships end the call without a duration', () {
      final entries = _callLog([
        _join(_bob, Duration.zero, expires: const Duration(minutes: 10)),
        _join(_alice, const Duration(hours: 1)),
        _leave(_alice, const Duration(hours: 1, minutes: 1)),
      ]);
      expect(entries.length, 2);
      expect(entries.first.initiatorId, _bob);
      expect(entries.first.end, null);
      expect(entries.first.isOngoing, false);
      expect(entries.last.direction, CallLogDirection.outgoing);
      expect(entries.last.duration, const Duration(minutes: 1));
    });

    test('Ongoing call', () {
      final entries = _callLog([
        _join(_bob, Duration.zero),
      ], now: const Duration(minutes: 5));
      expect(entries.single.isOngoing, true);
      expect(entries.single.end, null);
      expect(entries.single.direction, CallLogDirection.missed);
    });

    test('Refreshing a membership does not start a new call', () {
      final entries = _callLog([
        _join(_alice, Duration.zero),
        _join(_alice, const Duration(minutes: 1)),
        _leave(_alice, const Duration(minutes: 2)),
      ]);
      expect(entries.length, 1);
      expect(entries.single.duration, const Duration(minutes: 2));
    });

    test('Leave events without a known join are ignored', () {
      final entries = _callLog([
        _leave(_bob, Duration.zero),
        _join(_alice, const Duration(minutes: 1)),
        _leave(_alice, const Duration(minutes: 2)),
      ]);
      expect(entries.length, 1);
      expect(entries.single.initiatorId, _alice);
    });
  });
}
