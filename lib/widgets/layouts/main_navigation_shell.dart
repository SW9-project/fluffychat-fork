// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Displays the [MainNavigationBar] on top of the navigator with the pages of
/// the main tabs, so that the same bar stays while switching between them,
/// like a tab bar controller on iOS. It is only visible on the root pages of
/// the tabs.
class MainNavigationShell extends StatelessWidget {
  final String path;
  final Widget child;

  const MainNavigationShell({
    required this.path,
    required this.child,
    super.key,
  });

  /// Has to observe the navigator of the shell route, because dialogs and
  /// bottom sheets on top of a tab page are displayed below the bar.
  static final MainNavigationRouteObserver routeObserver =
      MainNavigationRouteObserver();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: ValueListenableBuilder(
          valueListenable: routeObserver.pagelessRouteOnTop,
          builder: (context, pagelessRouteOnTop, _) => MainNavigationBarHost(
            activeTab: MainNavigationTab.fromPath(path),
            visible: MainNavigationTab.isRootPath(path) && !pagelessRouteOnTop,
          ),
        ),
      ),
    ],
  );
}

/// Knows whether a route which is not a page of the router, like a dialog,
/// a bottom sheet or a menu, is on top of the navigator.
class MainNavigationRouteObserver extends NavigatorObserver {
  final ValueNotifier<bool> pagelessRouteOnTop = ValueNotifier(false);

  @override
  void didChangeTop(Route topRoute, Route? previousTopRoute) {
    // Might be called while the navigator is building.
    scheduleMicrotask(
      () => pagelessRouteOnTop.value = topRoute.settings is! Page,
    );
  }
}

/// Connects the [MainNavigationBar] with the router and the unread chats and
/// fades it out while it is not [visible] or the keyboard is open.
class MainNavigationBarHost extends StatelessWidget {
  final MainNavigationTab activeTab;
  final bool visible;

  const MainNavigationBarHost({
    required this.activeTab,
    this.visible = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final visible =
        this.visible && MediaQuery.viewInsetsOf(context).bottom == 0;
    final client = Matrix.of(context).client;

    Widget bar = StreamBuilder(
      key: ValueKey(client.userID.toString()),
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) => MainNavigationBar(
        activeTab: activeTab,
        unreadChats: client.rooms
            .where(
              (room) => room.isUnread || room.membership == Membership.invite,
            )
            .length,
        onTabSelected: (tab) => context.go(tab.path),
      ),
    );
    // Moving the native bar would make UIKit lay it out again for the
    // changing safe area, so it only fades.
    if (!PlatformInfos.supportsLiquidGlass) {
      bar = AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.3),
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: bar,
      );
    }

    bar = IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          child: bar,
        ),
      ),
    );

    // Android puts a translucent scrim behind the navigation buttons, which
    // would cut off the content and the shadow below the bar. The bar fades
    // the content out itself.
    final overlayStyle = Theme.of(context).appBarTheme.systemOverlayStyle;
    if (overlayStyle == null) return bar;
    return AnnotatedRegion(
      value: overlayStyle.copyWith(
        systemNavigationBarContrastEnforced: !visible,
      ),
      child: bar,
    );
  }
}
