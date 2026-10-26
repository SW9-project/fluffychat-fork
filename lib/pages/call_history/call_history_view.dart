// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/call_history/call_history.dart';
import 'package:fluffychat/pages/call_history/call_log_list_item.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

class CallHistoryView extends StatelessWidget {
  final CallHistoryController controller;

  const CallHistoryView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = controller.entries;
    final error = controller.error;

    return MainNavigationBarInsets(
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).calls),
          automaticallyImplyLeading: false,
        ),
        body: RefreshIndicator.adaptive(
          onRefresh: controller.loadCallLog,
          child: entries == null || entries.isEmpty
              ? CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: entries == null && error == null
                          ? const Center(
                              child: CircularProgressIndicator.adaptive(),
                            )
                          : _CallHistoryPlaceholder(
                              icon: error == null
                                  ? CupertinoIcons.phone
                                  : Icons.error_outline,
                              title: error == null
                                  ? L10n.of(context).noCallsYet
                                  : L10n.of(context).oopsSomethingWentWrong,
                              description: error == null
                                  ? L10n.of(context).callHistoryDescription
                                  : error.toLocalizedString(context),
                              action: error == null
                                  ? null
                                  : TextButton(
                                      onPressed: controller.loadCallLog,
                                      child: Text(L10n.of(context).tryAgain),
                                    ),
                            ),
                    ),
                  ],
                )
              : ValueListenableBuilder(
                  valueListenable: Matrix.of(context).activeCallRoomId,
                  builder: (context, _, _) => ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: entries.length,
                    separatorBuilder: (context, _) => Divider(
                      height: 0.5,
                      indent: CallLogListItem.dividerIndent,
                      color: theme.dividerColor,
                    ),
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      final room = controller.client.getRoomById(entry.roomId);
                      if (room == null) return const SizedBox.shrink();
                      return CallLogListItem(
                        key: ValueKey('${entry.roomId}_${entry.start}'),
                        entry: entry,
                        room: room,
                        onTap: () => controller.openChat(room),
                        onCall: controller.canStartCall(room)
                            ? () => controller.startCall(room)
                            : null,
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

class _CallHistoryPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  const _CallHistoryPlaceholder({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: .min,
          spacing: 8,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.secondary),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
