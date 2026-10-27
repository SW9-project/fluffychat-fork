// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Returns the ID of the selected chat or null if the dialog was dismissed.
Future<String?> showChatPickerDialog({
  required BuildContext context,
  required String title,
}) => showScaffoldDialog<String>(
  context: context,
  builder: (context) => _ChatPickerDialog(title: title),
);

class _ChatPickerDialog extends StatefulWidget {
  final String title;

  const _ChatPickerDialog({required this.title});

  @override
  State<_ChatPickerDialog> createState() => _ChatPickerDialogState();
}

class _ChatPickerDialogState extends State<_ChatPickerDialog> {
  final TextEditingController _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = _filterController.text.trim().toLowerCase();
    final rooms = Matrix.of(context).client.rooms
        .where((room) => !room.isSpace && room.membership == Membership.join)
        .map(
          (room) => (
            room: room,
            displayname: room.getLocalizedDisplayname(
              MatrixLocals(L10n.of(context)),
            ),
          ),
        )
        .where((item) => item.displayname.toLowerCase().contains(filter))
        .toList();
    return Scaffold(
      appBar: AppBar(
        leading: Center(
          child: CloseButton(onPressed: () => Navigator.of(context).pop()),
        ),
        title: Text(widget.title),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            toolbarHeight: 72,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: TextField(
              controller: _filterController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.colorScheme.secondaryContainer,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(99),
                ),
                contentPadding: EdgeInsets.zero,
                hintText: L10n.of(context).search,
                hintStyle: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.normal,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: Icon(
                  Icons.search_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final (:room, :displayname) = rooms[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: FutureBuilder(
                  future: room.loadHeroUsers(),
                  builder: (context, _) => ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius,
                      ),
                    ),
                    leading: Avatar(
                      mxContent: room.avatar,
                      name: displayname,
                      size: Avatar.defaultSize * 0.75,
                    ),
                    title: Text(
                      displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(room.id),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
