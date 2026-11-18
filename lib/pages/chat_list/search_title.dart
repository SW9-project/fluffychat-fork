// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

class SearchTitle extends StatelessWidget {
  final String title;
  final Widget icon;
  final Widget? trailing;
  final void Function()? onTap;
  final Color? color;

  const SearchTitle({
    required this.title,
    required this.icon,
    this.trailing,
    this.onTap,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A section header of iOS: a bold title without icon and dividers.
    if (theme.cupertinoStyle) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          color: color,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );
    }

    return Material(
      shape: Border(
        top: BorderSide(color: theme.dividerColor, width: 1),
        bottom: BorderSide(color: theme.dividerColor, width: 1),
      ),
      color: color ?? theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        splashColor: theme.colorScheme.surface,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: IconTheme(
              data: theme.iconTheme.copyWith(size: 16),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 16),
                  Text(
                    title,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (trailing != null)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
