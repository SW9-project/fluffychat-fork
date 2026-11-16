// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Row of colors for own message bubbles. The first entry is `null`, which
/// means [nullLabel], the app default.
/// [disabled] is the color of the other side, which can not be picked.
class BubbleColorPicker extends StatelessWidget {
  final Color? selected;
  final Color? disabled;
  final ValueChanged<Color?> onSelected;
  final String nullLabel;

  const BubbleColorPicker({
    required this.selected,
    required this.onSelected,
    required this.nullLabel,
    this.disabled,
    super.key,
  });

  static const double _size = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [null, ...Colors.primaries].map((color) {
          final isSelected = color?.toARGB32() == selected?.toARGB32();
          final isDisabled =
              color != null && color.toARGB32() == disabled?.toARGB32();
          final fill = color ?? theme.colorScheme.surfaceContainerHighest;
          return Semantics(
            selected: isSelected,
            enabled: !isDisabled,
            button: true,
            child: Tooltip(
              message: color == null
                  ? nullLabel
                  : '#${color.toARGB32().toRadixString(16).toUpperCase()}',
              child: InkWell(
                borderRadius: BorderRadius.circular(_size),
                onTap: isDisabled ? null : () => onSelected(color),
                child: Material(
                  color: isDisabled ? fill.withAlpha(60) : fill,
                  elevation: 6,
                  shape: const CircleBorder(),
                  child: SizedBox.square(
                    dimension: _size,
                    child: Icon(
                      isSelected
                          ? Icons.check
                          : isDisabled
                          ? Icons.block
                          : color == null
                          ? Icons.format_color_reset_outlined
                          : null,
                      size: 16,
                      color:
                          ThemeData.estimateBrightnessForColor(fill) ==
                              Brightness.light
                          ? Colors.black
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Applies the chat's bubble color (or the general one) to [child] and
/// rebuilds when either changes.
class BubbleColorScope extends StatelessWidget {
  final Room room;
  final Widget child;

  const BubbleColorScope({required this.room, required this.child, super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: room.onConfigChange,
    // Always wrap in Theme so the child keeps its state when the color changes.
    builder: (context, _) => Theme(
      data: Theme.of(
        context,
      ).withBubbleColors(room.bubbleColor, room.otherBubbleColor),
      child: child,
    ),
  );
}
