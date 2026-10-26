// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

class TwoColumnLayout extends StatelessWidget {
  final Widget mainView;
  final Widget sideView;
  final bool hasNavigationRail;

  /// Floats at the bottom of the main view, next to the navigation rail.
  final Widget? bottomBar;

  const TwoColumnLayout({
    super.key,
    required this.mainView,
    required this.sideView,
    this.hasNavigationRail = true,
    this.bottomBar,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomBar = this.bottomBar;

    return ScaffoldMessenger(
      child: Scaffold(
        body: Row(
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              width:
                  FluffyThemes.columnWidth +
                  (hasNavigationRail ? FluffyThemes.navRailWidth : 0),
              child: Stack(
                children: [
                  Positioned.fill(child: mainView),
                  if (bottomBar != null)
                    Positioned(
                      left: hasNavigationRail ? FluffyThemes.navRailWidth : 0,
                      right: 0,
                      bottom: 0,
                      child: bottomBar,
                    ),
                ],
              ),
            ),
            Container(width: 1.0, color: theme.dividerColor),
            Expanded(child: ClipRRect(child: sideView)),
          ],
        ),
      ),
    );
  }
}
