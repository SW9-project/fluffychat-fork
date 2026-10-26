// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:matrix/matrix.dart';

enum CallLogDirection { outgoing, incoming, missed }

/// A call in a room, reconstructed from the history of the
/// `org.matrix.msc3401.call.member` state events of the room. Unlike the
/// rtc notification events, those are never encrypted so they can be
/// filtered on the server.
class CallLogEntry {
  final String roomId;
  final String initiatorId;
  final DateTime start;

  /// Is null if the call is still ongoing or if the memberships of the last
  /// participants have just expired instead of them leaving the call.
  final DateTime? end;
  final MatrixRtcCallIntent intent;
  final Set<String> participantIds;
  final CallLogDirection direction;
  final bool isOngoing;

  const CallLogEntry({
    required this.roomId,
    required this.initiatorId,
    required this.start,
    required this.end,
    required this.intent,
    required this.participantIds,
    required this.direction,
    required this.isOngoing,
  });

  Duration? get duration => end?.difference(start);
}

/// Memberships without a valid `expires` field are treated like the ones
/// FluffyChat sends.
const Duration _defaultMembershipLifetime = Duration(hours: 4);

/// Reconstructs the calls of a room from its call member state events. A call
/// starts when the first device joins and ends when the last device has left
/// or its membership has expired.
List<CallLogEntry> callLogFromCallMemberEvents(
  String roomId,
  Iterable<MatrixEvent> events, {
  required String ownUserId,
  DateTime? now,
}) {
  final entries = <CallLogEntry>[];
  // State key of every device in the call with the time its membership expires.
  final activeDevices = <String, DateTime>{};
  _PendingCall? call;

  void endCall({DateTime? end, bool isOngoing = false}) {
    final pendingCall = call;
    if (pendingCall == null) return;
    entries.add(
      CallLogEntry(
        roomId: roomId,
        initiatorId: pendingCall.initiatorId,
        start: pendingCall.start,
        end: end,
        intent: pendingCall.intent,
        participantIds: pendingCall.participantIds,
        direction: pendingCall.initiatorId == ownUserId
            ? CallLogDirection.outgoing
            : pendingCall.participantIds.contains(ownUserId)
            ? CallLogDirection.incoming
            : CallLogDirection.missed,
        isOngoing: isOngoing,
      ),
    );
    call = null;
  }

  final sortedEvents = events
      .where(
        (event) =>
            event.type == MatrixRtcCallMember.eventType &&
            event.stateKey != null,
      )
      .sortedBy((event) => event.originServerTs);

  for (final event in sortedEvents) {
    final timestamp = event.originServerTs;

    // Devices which have lost their connection might never leave the call so
    // their memberships just expire.
    activeDevices.removeWhere((_, expiresAt) => expiresAt.isBefore(timestamp));
    if (activeDevices.isEmpty) endCall();

    final membership = _tryParseCallMembership(event);
    if (membership == null) {
      if (activeDevices.remove(event.stateKey) != null &&
          activeDevices.isEmpty) {
        endCall(end: timestamp);
      }
      continue;
    }

    final lifetime = membership.expires > Duration.zero
        ? membership.expires
        : _defaultMembershipLifetime;
    activeDevices[event.stateKey!] = (membership.createdAt ?? timestamp).add(
      lifetime,
    );
    (call ??= _PendingCall(
      initiatorId: event.senderId,
      start: timestamp,
      intent: membership.callIntent,
    )).participantIds.add(event.senderId);
  }

  now ??= DateTime.now();
  activeDevices.removeWhere((_, expiresAt) => expiresAt.isBefore(now!));
  endCall(isOngoing: activeDevices.isNotEmpty);

  return entries;
}

/// Returns null if the event means that the device has left the call.
MatrixRtcCallMember? _tryParseCallMembership(MatrixEvent event) {
  final content = event.content;
  if (content.isEmpty) return null;
  // Legacy format with a list of memberships per user:
  final legacyMemberships = content['memberships'];
  if (legacyMemberships is List && legacyMemberships.isEmpty) return null;

  try {
    final membership = MatrixRtcCallMember.fromJson(
      content,
      senderId: event.senderId,
    );
    if (membership.application.isNotEmpty &&
        membership.application != 'm.call') {
      return null;
    }
    return membership;
  } catch (e, s) {
    Logs().d('Invalid "${MatrixRtcCallMember.eventType}" event!', e, s);
    return null;
  }
}

class _PendingCall {
  final String initiatorId;
  final DateTime start;
  final MatrixRtcCallIntent intent;
  final Set<String> participantIds = {};

  _PendingCall({
    required this.initiatorId,
    required this.start,
    required this.intent,
  });
}

extension MatrixRtcCallLogRoomExtension on Room {
  /// Whether a MatrixRTC call has ever taken place in this room. Call member
  /// states stay in the room state, even after everyone has left.
  bool get hasMatrixRtcCallHistory =>
      states[MatrixRtcCallMember.eventType]?.isNotEmpty ?? false;

  Future<List<CallLogEntry>> getMatrixRtcCallLog({int limit = 50}) async {
    final response = await client.getRoomEvents(
      id,
      Direction.b,
      limit: limit,
      filter: jsonEncode({
        'types': [MatrixRtcCallMember.eventType],
      }),
    );
    final entries = callLogFromCallMemberEvents(
      id,
      response.chunk,
      ownUserId: client.userID!,
    );
    // If there is more history, the oldest call might have started before
    // the loaded events and would be incomplete.
    if (response.chunk.length >= limit && entries.isNotEmpty) {
      entries.removeAt(0);
    }
    return entries;
  }
}

extension MatrixRtcCallLogClientExtension on Client {
  static const int _concurrentRequests = 5;

  /// Loads the recent calls of all joined rooms, newest first.
  Future<List<CallLogEntry>> getMatrixRtcCallLog() async {
    final rooms = this.rooms
        .where(
          (room) =>
              room.membership == Membership.join &&
              room.hasMatrixRtcCallHistory,
        )
        .toList();

    final entries = <CallLogEntry>[];
    Object? lastError;
    var failedRooms = 0;
    for (final batch in rooms.slices(_concurrentRequests)) {
      await Future.wait(
        batch.map((room) async {
          try {
            entries.addAll(await room.getMatrixRtcCallLog());
          } catch (e, s) {
            Logs().w('Unable to load call history of ${room.id}', e, s);
            lastError = e;
            failedRooms++;
          }
        }),
      );
    }
    final error = lastError;
    if (error != null && failedRooms == rooms.length) throw error;

    return entries..sort((a, b) => b.start.compareTo(a.start));
  }
}
