// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../config/app_config.dart';

class ReplyContent extends StatelessWidget {
  final Event replyEvent;
  final bool ownMessage;
  final Timeline? timeline;

  const ReplyContent(
    this.replyEvent, {
    this.ownMessage = false,
    super.key,
    this.timeline,
  });

  static const BorderRadius borderRadius = BorderRadius.all(Radius.circular(4));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final timeline = this.timeline;
    final displayEvent = timeline != null
        ? replyEvent.getDisplayEvent(timeline)
        : replyEvent;
    const fontSize = AppConfig.messageFontSize - 2;
    final color = ownMessage ? theme.bubbleAccentColor : theme.bubbleLinkColor;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        decoration: BoxDecoration(
          color: color.withAlpha(32),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: .min,
          children: <Widget>[
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: .start,
                mainAxisAlignment: .center,
                children: <Widget>[
                  FutureBuilder<User?>(
                    initialData: displayEvent.senderFromMemoryOrFallback,
                    future: displayEvent.fetchSenderUser(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data?.calcDisplayname() ??
                            displayEvent.senderFromMemoryOrFallback
                                .calcDisplayname(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: color,
                          fontSize: fontSize,
                        ),
                      );
                    },
                  ),
                  Text(
                    displayEvent
                        .calcLocalizedBodyFallback(
                          MatrixLocals(L10n.of(context)),
                          withSenderNamePrefix: false,
                          hideReply: true,
                          plaintextBody: true,
                        )
                        .trim()
                        .replaceAll('\n', ' '),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: ownMessage
                          ? theme.onBubbleColor
                          : theme.colorScheme.onSurface,
                      fontSize: fontSize,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
