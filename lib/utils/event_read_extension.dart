// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension EventReadExtension on Event {
  /// Whether another user has sent a read receipt for this event or after
  /// this event was sent. Used to display the double checkmark.
  bool get isReadByOthers {
    final sentAt = originServerTs.millisecondsSinceEpoch;
    bool readIn(LatestReceiptStateForTimeline? receipts) =>
        receipts?.otherUsers.values.any(
          (receipt) => receipt.eventId == eventId || receipt.ts >= sentAt,
        ) ??
        false;
    return readIn(room.receiptState.global) ||
        readIn(room.receiptState.mainThread);
  }
}
