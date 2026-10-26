// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_rtc_call_log.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class CallLogListItem extends StatelessWidget {
  final CallLogEntry entry;
  final Room room;
  final VoidCallback onTap;
  final VoidCallback? onCall;

  const CallLogListItem({
    required this.entry,
    required this.room,
    required this.onTap,
    required this.onCall,
    super.key,
  });

  static const double _avatarSize = 48.0;
  static const double _horizontalPadding = 12.0;
  static const double dividerIndent = _horizontalPadding * 2 + _avatarSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final displayname = room.getLocalizedDisplayname(MatrixLocals(l10n));
    final missed =
        entry.direction == CallLogDirection.missed && !entry.isOngoing;
    final isVideo = entry.intent == .video;

    final duration = entry.duration;
    final status = entry.isOngoing
        ? l10n.ongoingCall
        : switch (entry.direction) {
            CallLogDirection.outgoing => l10n.outgoingCall,
            CallLogDirection.incoming => l10n.incomingCall,
            CallLogDirection.missed => l10n.missedCall,
          };
    final statusColor = entry.isOngoing
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return ListTile(
      minVerticalPadding: 8,
      horizontalTitleGap: _horizontalPadding,
      contentPadding: const EdgeInsets.only(
        left: _horizontalPadding,
        right: _horizontalPadding / 2,
      ),
      onTap: onTap,
      leading: Avatar(
        mxContent: room.avatar,
        name: displayname,
        size: _avatarSize,
        presenceUserId: room.directChatMatrixID,
      ),
      title: Text(
        displayname,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: missed ? theme.colorScheme.error : null,
        ),
      ),
      subtitle: Row(
        spacing: 4,
        children: [
          Icon(
            entry.isOngoing
                ? isVideo
                      ? CupertinoIcons.video_camera_solid
                      : CupertinoIcons.phone_fill
                : entry.direction == CallLogDirection.outgoing
                ? CupertinoIcons.arrow_up_right
                : CupertinoIcons.arrow_down_left,
            size: 14,
            color: missed ? theme.colorScheme.error : statusColor,
          ),
          Flexible(
            child: Text(
              [
                status,
                if (duration != null && !missed) _formatDuration(duration),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: statusColor),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: .min,
        children: [
          Text(
            entry.start.localizedTimeShort(context),
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: entry.isOngoing
                ? l10n.enterCall
                : isVideo
                ? l10n.videoCall
                : l10n.voiceCall,
            color: theme.colorScheme.primary,
            onPressed: onCall,
            icon: Icon(
              isVideo ? CupertinoIcons.video_camera : CupertinoIcons.phone,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes % 60;
    final seconds = twoDigits(duration.inSeconds % 60);
    return duration.inHours > 0
        ? '${duration.inHours}:${twoDigits(minutes)}:$seconds'
        : '$minutes:$seconds';
  }
}
