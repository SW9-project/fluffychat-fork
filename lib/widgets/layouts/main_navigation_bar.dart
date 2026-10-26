// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'dart:ui' as ui;

import 'package:badges/badges.dart' as b;
import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The main sections of the app, reachable from the [MainNavigationBar].
enum MainNavigationTab {
  chats('/rooms'),
  calls('/rooms/calls'),
  assistant('/rooms/assistant'),
  settings('/rooms/settings');

  final String path;

  const MainNavigationTab(this.path);

  /// Returns the tab which the given location belongs to.
  static MainNavigationTab fromPath(String path) =>
      [calls, assistant, settings].firstWhereOrNull(
        (tab) => path == tab.path || path.startsWith('${tab.path}/'),
      ) ??
      chats;

  /// Whether the location is the root page of a tab, which displays the
  /// navigation bar.
  static bool isRootPath(String path) => values.any((tab) => tab.path == path);

  String localizedLabel(L10n l10n) => switch (this) {
    chats => l10n.chats,
    calls => l10n.calls,
    assistant => l10n.assistant,
    settings => l10n.settings,
  };

  /// Filled in every state, like the SF Symbols of the native tab bar.
  IconData get icon => switch (this) {
    chats => CupertinoIcons.chat_bubble_2_fill,
    calls => CupertinoIcons.phone_fill,
    assistant => CupertinoIcons.sparkles,
    settings => CupertinoIcons.gear_alt_fill,
  };

  /// Icon of the native tab bar on iOS.
  String get sfSymbol => switch (this) {
    chats => 'bubble.left.and.bubble.right.fill',
    calls => 'phone.fill',
    assistant => 'sparkles',
    settings => 'gearshape.fill',
  };
}

/// Floating navigation bar between the main tabs. On iOS 26 and newer it is
/// the native tab bar with Liquid Glass, everywhere else Flutter draws it in
/// the same style.
class MainNavigationBar extends StatelessWidget {
  final MainNavigationTab activeTab;
  final ValueChanged<MainNavigationTab> onTabSelected;
  final int unreadChats;

  const MainNavigationBar({
    required this.activeTab,
    required this.onTabSelected,
    this.unreadChats = 0,
    super.key,
  });

  /// The space at the bottom of the screen which is covered by the bar,
  /// including the space below it.
  static double occupiedHeight(BuildContext context) =>
      PlatformInfos.supportsLiquidGlass
      ? _NativeTabBar.height(context)
      : _GlassTabBar.height + _GlassTabBar.bottomMargin(context);

  /// Notifies when [occupiedHeight] changes because UIKit has measured the
  /// native bar.
  static Listenable get occupiedHeightChanges => _NativeTabBar.reportedHeight;

  @override
  Widget build(BuildContext context) => PlatformInfos.supportsLiquidGlass
      ? _NativeTabBar(
          activeTab: activeTab,
          onTabSelected: onTabSelected,
          unreadChats: unreadChats,
        )
      : _GlassTabBar(
          activeTab: activeTab,
          onTabSelected: onTabSelected,
          unreadChats: unreadChats,
        );
}

/// Adds the space covered by the [MainNavigationBar] to the bottom padding,
/// so that the content of a tab page can be scrolled above the bar and
/// floating action buttons and snack bars are placed above it.
class MainNavigationBarInsets extends StatelessWidget {
  final Widget child;

  /// Keeps the widget tree the same while the insets are not needed.
  final bool enabled;

  const MainNavigationBarInsets({
    required this.child,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: MainNavigationBar.occupiedHeightChanges,
    builder: (context, child) {
      final mediaQuery = MediaQuery.of(context);
      // The bar is hidden while the keyboard is open.
      final bottom = !enabled || mediaQuery.viewInsets.bottom > 0
          ? 0.0
          : MainNavigationBar.occupiedHeight(context);
      return MediaQuery(
        data: mediaQuery.copyWith(
          padding: mediaQuery.padding.copyWith(
            bottom: max(mediaQuery.padding.bottom, bottom),
          ),
          viewPadding: mediaQuery.viewPadding.copyWith(
            bottom: max(mediaQuery.viewPadding.bottom, bottom),
          ),
        ),
        child: child!,
      );
    },
    child: child,
  );
}

/// A `UITabBar` embedded as a platform view, see `LiquidGlassTabBar.swift`.
class _NativeTabBar extends StatefulWidget {
  final MainNavigationTab activeTab;
  final ValueChanged<MainNavigationTab> onTabSelected;
  final int unreadChats;

  const _NativeTabBar({
    required this.activeTab,
    required this.onTabSelected,
    required this.unreadChats,
  });

  static const String _viewType = 'fluffychat/liquid_glass_tab_bar';

  /// The height UIKit needs for the bar, including the space between the
  /// floating bar and the bottom of the screen.
  static final ValueNotifier<double?> reportedHeight = ValueNotifier(null);

  /// Until UIKit has measured the bar, this is the height of a classic tab
  /// bar, which has the same size.
  static double height(BuildContext context) =>
      reportedHeight.value ?? 49 + MediaQuery.viewPaddingOf(context).bottom;

  /// Hands touches to the native bar right away, so that the selection can
  /// be dragged between the tabs.
  static final Set<Factory<OneSequenceGestureRecognizer>> _gestureRecognizers =
      {Factory(EagerGestureRecognizer.new)};

  @override
  State<_NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<_NativeTabBar> {
  MethodChannel? _channel;
  Map<String, Object?>? _sentState;

  Map<String, Object?> _state() {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    const tabs = MainNavigationTab.values;
    return {
      'labels': [for (final tab in tabs) tab.localizedLabel(l10n)],
      'symbols': [for (final tab in tabs) tab.sfSymbol],
      'badges': [
        for (final tab in tabs)
          tab == MainNavigationTab.chats && widget.unreadChats > 0
              ? widget.unreadChats.toString()
              : null,
      ],
      'selectedIndex': widget.activeTab.index,
      'tintColor': theme.colorScheme.primary.toARGB32(),
      'isDark': theme.brightness == Brightness.dark,
    };
  }

  void _sendState() {
    final channel = _channel;
    if (channel == null) return;
    final state = _state();
    if (const DeepCollectionEquality().equals(state, _sentState)) return;
    _sentState = state;
    channel.invokeMethod('update', state);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sendState();
  }

  @override
  void didUpdateWidget(_NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sendState();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('${_NativeTabBar._viewType}/$id')
      ..setMethodCallHandler(_onMethodCall);
    _sendState();
  }

  Future<void> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'tabSelected':
        final tab = MainNavigationTab.values.elementAtOrNull(
          call.arguments as int,
        );
        if (tab != null && tab != widget.activeTab) widget.onTabSelected(tab);
      case 'heightChanged':
        _NativeTabBar.reportedHeight.value = (call.arguments as num).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _NativeTabBar.reportedHeight,
    builder: (context, _, _) => SizedBox(
      height: _NativeTabBar.height(context),
      child: UiKitView(
        viewType: _NativeTabBar._viewType,
        creationParams: _state(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: _NativeTabBar._gestureRecognizers,
      ),
    ),
  );
}

/// The bar drawn by Flutter with [LiquidGlass] for all other platforms.
class _GlassTabBar extends StatefulWidget {
  final MainNavigationTab activeTab;
  final ValueChanged<MainNavigationTab> onTabSelected;
  final int unreadChats;

  const _GlassTabBar({
    required this.activeTab,
    required this.onTabSelected,
    required this.unreadChats,
  });

  static const double height = 62.0;

  /// Like the native bar, it overlaps the home indicator on iOS. On Android
  /// it stays right above the gesture handle or the navigation buttons.
  static double bottomMargin(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return PlatformInfos.isIOS ? max(bottom - 13, 12) : max(bottom + 4, 16);
  }

  @override
  State<_GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<_GlassTabBar>
    with SingleTickerProviderStateMixin {
  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 22,
  );

  late final AnimationController _indicatorController =
      AnimationController.unbounded(vsync: this, value: 1);

  late double _indicatorStart = widget.activeTab.index.toDouble();

  @override
  void didUpdateWidget(_GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab) {
      _indicatorStart = _indicatorPosition(oldWidget.activeTab);
      _indicatorController.animateWith(SpringSimulation(_spring, 0, 1, 0));
    }
  }

  @override
  void dispose() {
    _indicatorController.dispose();
    super.dispose();
  }

  double _indicatorPosition(MainNavigationTab target) => ui.lerpDouble(
    _indicatorStart,
    target.index.toDouble(),
    _indicatorController.value,
  )!;

  void _onTap(MainNavigationTab tab) {
    if (tab == widget.activeTab) return;
    HapticFeedback.selectionClick();
    widget.onTabSelected(tab);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    const borderRadius = BorderRadius.all(
      Radius.circular(_GlassTabBar.height / 2),
    );
    final indicatorColor = theme.colorScheme.onSurface.withValues(
      alpha: theme.brightness == Brightness.light ? 0.07 : 0.12,
    );

    final bar = Padding(
      padding: EdgeInsets.fromLTRB(
        20 + padding.left,
        0,
        20 + padding.right,
        _GlassTabBar.bottomMargin(context),
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 440,
            minHeight: _GlassTabBar.height,
            maxHeight: _GlassTabBar.height,
          ),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: LiquidGlass(
              borderRadius: borderRadius,
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth =
                          constraints.maxWidth /
                          MainNavigationTab.values.length;
                      // The items fill the height of the bar, so that their
                      // content is centered like the indicator behind them.
                      return Stack(
                        fit: .expand,
                        children: [
                          AnimatedBuilder(
                            animation: _indicatorController,
                            builder: (context, _) {
                              final position = _indicatorPosition(
                                widget.activeTab,
                              );
                              // Like a drop of liquid, the indicator
                              // stretches while it moves.
                              final distance =
                                  (widget.activeTab.index - _indicatorStart)
                                      .abs();
                              final stretch =
                                  sin(
                                    _indicatorController.value.clamp(0, 1) * pi,
                                  ) *
                                  min(distance, 1) *
                                  0.25;
                              final width = itemWidth * (1 + stretch);
                              return Positioned(
                                left:
                                    position * itemWidth -
                                    (width - itemWidth) / 2,
                                width: width,
                                top: stretch * 4,
                                bottom: stretch * 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: borderRadius,
                                    color: indicatorColor,
                                  ),
                                ),
                              );
                            },
                          ),
                          Row(
                            crossAxisAlignment: .stretch,
                            children: MainNavigationTab.values
                                .map(
                                  (tab) => Expanded(
                                    child: _GlassTabBarItem(
                                      tab: tab,
                                      label: tab.localizedLabel(l10n),
                                      selected: tab == widget.activeTab,
                                      badge:
                                          tab == MainNavigationTab.chats &&
                                              widget.unreadChats > 0
                                          ? widget.unreadChats.toString()
                                          : null,
                                      onTap: () => _onTap(tab),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Since Android 15 the system navigation is drawn on top of the content.
    // Like the scroll edge effect on iOS, the content fades out below the
    // bar, so that the navigation buttons stay readable.
    if (!PlatformInfos.isAndroid || padding.bottom == 0) return bar;
    final fadeHeight =
        _GlassTabBar.height / 2 + _GlassTabBar.bottomMargin(context);
    final fadeColor = theme.colorScheme.surface;
    return Stack(
      // Keeps the shadow of the bar.
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: fadeHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    fadeColor.withValues(alpha: 0),
                    fadeColor.withValues(alpha: 0.9),
                    fadeColor.withValues(alpha: 0.9),
                  ],
                  stops: [0, 1 - padding.bottom / fadeHeight, 1],
                ),
              ),
            ),
          ),
        ),
        bar,
      ],
    );
  }
}

class _GlassTabBarItem extends StatefulWidget {
  final MainNavigationTab tab;
  final String label;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  const _GlassTabBarItem({
    required this.tab,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_GlassTabBarItem> createState() => _GlassTabBarItemState();
}

class _GlassTabBarItemState extends State<_GlassTabBarItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final badge = widget.badge;

    return Semantics(
      container: true,
      selected: widget.selected,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        customBorder: const StadiumBorder(),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: color.withValues(alpha: 0.04),
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: .center,
            mainAxisSize: .min,
            spacing: 2,
            children: [
              b.Badge(
                showBadge: badge != null,
                position: b.BadgePosition.topEnd(top: -8, end: -20),
                badgeAnimation: const b.BadgeAnimation.scale(),
                // Red like the badges of the native tab bar.
                badgeStyle: b.BadgeStyle(
                  badgeColor: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemRed,
                    context,
                  ),
                ),
                badgeContent: Text(
                  badge ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                child: Icon(widget.tab.icon, size: 24, color: color),
              ),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
