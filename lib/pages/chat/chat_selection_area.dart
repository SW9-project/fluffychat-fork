// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/text_to_speech.dart';
import 'package:material_ui/material_ui.dart';

/// The selection area around the chat timeline.
///
/// Keeps the stock text selection toolbar and adds "Play", which reads the
/// selected text aloud on the device.
class ChatSelectionArea extends StatefulWidget {
  final Widget child;

  const ChatSelectionArea({super.key, required this.child});

  @override
  State<ChatSelectionArea> createState() => _ChatSelectionAreaState();
}

class _ChatSelectionAreaState extends State<ChatSelectionArea> {
  /// Not part of the build, so it is kept without setState.
  String _selectedText = '';

  Widget _buildContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: [
        ...selectableRegionState.contextMenuButtonItems,
        if (TextToSpeech.isSupported && _selectedText.trim().isNotEmpty)
          ContextMenuButtonItem(
            label: L10n.of(context).playSelectedText,
            onPressed: () {
              selectableRegionState.hideToolbar(false);
              TextToSpeech.instance.speak(_selectedText);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SelectionArea(
    onSelectionChanged: (content) => _selectedText = content?.plainText ?? '',
    contextMenuBuilder: _buildContextMenu,
    child: widget.child,
  );
}
