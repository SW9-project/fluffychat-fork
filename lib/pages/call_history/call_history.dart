// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/pages/call_history/call_history_view.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_rtc_call_log.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class CallHistory extends StatefulWidget {
  const CallHistory({super.key});

  @override
  CallHistoryController createState() => CallHistoryController();
}

class CallHistoryController extends State<CallHistory> {
  /// The last loaded call history per account, so that it can be displayed
  /// instantly while it gets refreshed.
  static final Map<String, List<CallLogEntry>> _cache = {};

  List<CallLogEntry>? entries;
  Object? error;

  StreamSubscription? _onCallMembersChanged;

  Client get client => Matrix.of(context).client;

  @override
  void initState() {
    super.initState();
    entries = _cache[client.userID];
    loadCallLog();
    _onCallMembersChanged = client.onSync.stream
        .where(
          (syncUpdate) => [
            ...?syncUpdate.rooms?.join?.values.expand(
              (room) => [...?room.timeline?.events, ...?room.state],
            ),
          ].any((event) => event.type == MatrixRtcCallMember.eventType),
        )
        .rateLimit(const Duration(seconds: 5))
        .listen((_) => loadCallLog());
  }

  @override
  void dispose() {
    _onCallMembersChanged?.cancel();
    super.dispose();
  }

  Future<void> loadCallLog() async {
    final client = this.client;
    try {
      final entries = (await client.getMatrixRtcCallLog())
          .where((entry) => client.getRoomById(entry.roomId) != null)
          .toList();
      _cache[client.userID!] = entries;
      if (!mounted) return;
      setState(() {
        this.entries = entries;
        error = null;
      });
    } catch (e, s) {
      Logs().w('Unable to load call history', e, s);
      if (!mounted) return;
      setState(() => error = e);
    }
  }

  void openChat(Room room) => context.go('/rooms/${room.id}');

  void startCall(Room room) =>
      Matrix.of(context).activeCallRoomId.value = room.id;

  bool canStartCall(Room room) =>
      room.hasPermissionForMatrixRtcCall &&
      Matrix.of(context).activeCallRoomId.value == null;

  @override
  Widget build(BuildContext context) => CallHistoryView(this);
}
