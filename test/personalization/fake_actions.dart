// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/assist/assist_actions.dart';
import 'package:fluffychat/personalization/model/app_change.dart';

/// App settings in memory: [values] by setting and chat, and every applied
/// change in [applied].
class FakeActions implements AssistActions {
  final Map<(AppSetting, String?), Object?> values = {};
  final List<AppChange> applied = [];

  @override
  Object? current(AppSetting setting, String? roomId) =>
      values[(setting, roomId)];

  @override
  Future<void> apply(AppChange change) async {
    applied.add(change);
    values[(change.setting, change.roomId)] = change.value;
  }
}
